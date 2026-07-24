import Foundation
import HealthRelayCore

struct LiveSyncOutcome: Sendable {
    let report: SyncReport
    let summary: SyncSummary
}

actor LiveSyncCoordinator {
    private static let stagedMetricsKey = "sync.lastStagedMetrics"
    private static let stagedBackfillStartKey = "sync.lastStagedBackfillStart"
    private static let stagedExportContractRevisionKey =
        "sync.lastStagedExportContractRevision"
    private static let destinationNamespaceKey =
        "sync.destinationAccountNamespace.v1"
    private static let exportContractRevision = 2

    private struct Runtime {
        let store: FileSyncStore
        let engine: SyncEngine
    }

    private let rootDirectory: URL
    private let healthKit: HealthKitClient
    private let recordProvider: HealthKitDailyRecordProvider
    private let destination: DriveArtifactDestination
    private let diagnostics: DiagnosticsRecorder
    private var runtime: Runtime
    private var lastSuccessfulSyncAt: Date?
    private var lastStagedMetrics: Set<HealthMetric>?
    private var lastStagedBackfillStart: LocalDate?
    private var lastStagedExportContractRevision: Int?
    private var destinationNamespace: String?
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        rootDirectory: URL,
        healthKit: HealthKitClient,
        recordProvider: HealthKitDailyRecordProvider,
        destination: DriveArtifactDestination,
        diagnostics: DiagnosticsRecorder
    ) throws {
        self.rootDirectory = rootDirectory
        self.healthKit = healthKit
        self.recordProvider = recordProvider
        self.destination = destination
        self.diagnostics = diagnostics
        lastSuccessfulSyncAt = UserDefaults.standard.object(
            forKey: "sync.lastSuccessful"
        ) as? Date
        lastStagedMetrics = UserDefaults.standard.stringArray(
            forKey: Self.stagedMetricsKey
        ).map { Set($0.compactMap(HealthMetric.init(rawValue:))) }
        lastStagedBackfillStart = UserDefaults.standard.string(
            forKey: Self.stagedBackfillStartKey
        ).flatMap { try? LocalDate(rawValue: $0) }
        lastStagedExportContractRevision = UserDefaults.standard.object(
            forKey: Self.stagedExportContractRevisionKey
        ) as? Int
        destinationNamespace = UserDefaults.standard.string(
            forKey: Self.destinationNamespaceKey
        )
        runtime = try Self.makeRuntime(
            rootDirectory: rootDirectory,
            recordProvider: recordProvider,
            destination: destination
        )
    }

    func prepare() async throws {
        try await runtime.store.recover()
    }

    func reconcile(
        trigger: SyncTrigger,
        enabledMetrics: Set<HealthMetric>,
        backfillStart: LocalDate
    ) async throws -> LiveSyncOutcome {
        await acquireOperation()
        defer { releaseOperation() }

        let calendar = LocalDayCalendar.current
        let backfillStartDate = backfillStart
        let missingDates = try await missingBackfillDates(
            from: backfillStartDate,
            calendar: calendar
        )
        let exportContractChanged =
            lastStagedExportContractRevision != Self.exportContractRevision
        if
            trigger == .retry,
            lastStagedMetrics == enabledMetrics,
            lastStagedBackfillStart == backfillStartDate,
            !exportContractChanged,
            missingDates.isEmpty
        {
            let report = try await runtime.engine.retryPendingUploads(force: true)
            return try await outcome(report: report)
        }

        let backfillStartInstant = try await healthKit.startDate(
            for: backfillStartDate
        )
        var dates = try BackfillDatePlanner.recentDates(
            through: .now,
            count: 3,
            notBefore: backfillStartDate,
            calendar: calendar
        )
        var batches: [HealthKitClient.AnchoredChangeBatch] = []
        let existingRecords = try await runtime.store.allDailyRecords()
        let existingDates = Set(existingRecords.map(\.date))
        let historyStart = Self.effectiveHistoryStart(
            requestedStart: backfillStartInstant,
            existingRecordDates: existingRecords.map(\.date)
        )
        await recordProvider.configure(
            earliestVO2Date: historyStart,
            enabledMetrics: enabledMetrics
        )
        let selectionChanged = lastStagedMetrics != enabledMetrics
        let backfillBoundaryChanged =
            lastStagedBackfillStart != backfillStartDate
        if selectionChanged || backfillBoundaryChanged || exportContractChanged {
            dates.formUnion(existingDates)
        }

        if trigger != .rebuild {
            for metric in HealthMetric.allCases where enabledMetrics.contains(metric) {
                let batch = try await healthKit.changedDates(
                    for: metric,
                    calendar: calendar,
                    notBefore: backfillStartInstant
                )
                batches.append(batch)
                let changedDates = try localDates(from: batch.affectedDates)
                dates.formUnion(
                    changedDates.filter {
                        $0 >= backfillStartDate || existingDates.contains($0)
                    }
                )

                if metric == .vo2Max, !batch.affectedDates.isEmpty {
                    dates.formUnion(existingDates)
                }
            }
            dates.formUnion(missingDates)
        }

        var report = try await stage(dates: dates)
        if selectionChanged {
            persistStagedMetrics(enabledMetrics)
        }
        if backfillBoundaryChanged {
            persistStagedBackfillStart(backfillStartDate)
        }
        if exportContractChanged {
            try await runtime.store.enqueueCurrentDailyArtifactsForUpload()
            persistStagedExportContractRevision()
        }
        for batch in batches {
            try await healthKit.commit(batch)
        }

        let uploadReport = try await runtime.engine.retryPendingUploads(
            force: trigger == .retry
        )
        merge(uploadReport, into: &report)
        return try await outcome(report: report)
    }

    func stageObservedChange(
        metric: HealthMetric,
        enabledMetrics: Set<HealthMetric>,
        backfillStart: LocalDate
    ) async throws {
        await acquireOperation()
        defer { releaseOperation() }

        guard enabledMetrics.contains(metric) else { return }
        let calendar = LocalDayCalendar.current
        let selectionChanged = lastStagedMetrics != enabledMetrics
        let backfillStartDate = backfillStart
        let backfillStartInstant = try await healthKit.startDate(
            for: backfillStartDate
        )
        let backfillBoundaryChanged =
            lastStagedBackfillStart != backfillStartDate
        let exportContractChanged =
            lastStagedExportContractRevision != Self.exportContractRevision
        let batch = try await healthKit.changedDates(
            for: metric,
            calendar: calendar,
            notBefore: backfillStartInstant
        )
        var dates = try BackfillDatePlanner.recentDates(
            through: .now,
            count: 3,
            notBefore: backfillStartDate,
            calendar: calendar
        )
        let existingRecords = try await runtime.store.allDailyRecords()
        let existingDates = Set(existingRecords.map(\.date))
        let historyStart = Self.effectiveHistoryStart(
            requestedStart: backfillStartInstant,
            existingRecordDates: existingRecords.map(\.date)
        )
        await recordProvider.configure(
            earliestVO2Date: historyStart,
            enabledMetrics: enabledMetrics
        )
        if selectionChanged || backfillBoundaryChanged || exportContractChanged {
            dates.formUnion(existingDates)
        }
        let changedDates = try localDates(from: batch.affectedDates)
        dates.formUnion(
            changedDates.filter {
                $0 >= backfillStartDate || existingDates.contains($0)
            }
        )
        dates.formUnion(
            try await missingBackfillDates(
                from: backfillStartDate,
                calendar: calendar
            )
        )
        if metric == .vo2Max, !batch.affectedDates.isEmpty {
            dates.formUnion(existingDates)
        }

        _ = try await stage(dates: dates)
        if selectionChanged {
            persistStagedMetrics(enabledMetrics)
        }
        if backfillBoundaryChanged {
            persistStagedBackfillStart(backfillStartDate)
        }
        if exportContractChanged {
            try await runtime.store.enqueueCurrentDailyArtifactsForUpload()
            persistStagedExportContractRevision()
        }
        try await healthKit.commit(batch)
    }

    func flushPendingUploads() async throws -> LiveSyncOutcome {
        await acquireOperation()
        defer { releaseOperation() }

        let report = try await runtime.engine.retryPendingUploads()
        return try await outcome(report: report)
    }

    func resumeAfterReauthorization() async throws -> LiveSyncOutcome {
        await acquireOperation()
        defer { releaseOperation() }

        let report = try await runtime.engine.resumeAfterReauthorization()
        return try await outcome(report: report)
    }

    func waitUntilIdle() async {
        await acquireOperation()
        releaseOperation()
    }

    func prepareDestination(
        destinationNamespace newDestinationNamespace: String
    ) async throws -> SyncSummary {
        await acquireOperation()
        defer { releaseOperation() }

        if destinationNamespace != newDestinationNamespace {
            try await runtime.store.resetRemoteUploadState()
            lastSuccessfulSyncAt = nil
            UserDefaults.standard.removeObject(forKey: "sync.lastSuccessful")
            destinationNamespace = newDestinationNamespace
            UserDefaults.standard.set(
                newDestinationNamespace,
                forKey: Self.destinationNamespaceKey
            )
        }
        return try await summary()
    }

    func summary() async throws -> SyncSummary {
        let records = try await runtime.store.allDailyRecords()
        let retryItems = try await runtime.store.retryItems()
        return SyncSummary(
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            latestExportedDate: records.map(\.date).max()?.rawValue,
            pendingUploadCount: retryItems.count,
            retryableUploadCount: retryItems.count {
                $0.blockReason == nil
            },
            permanentFailureCount: retryItems.count {
                $0.blockReason == .permanentFailure
            }
        )
    }

    func reset() async throws {
        await acquireOperation()
        defer { releaseOperation() }

        try await healthKit.resetAnchors()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.removeItem(at: rootDirectory)
        }
        runtime = try Self.makeRuntime(
            rootDirectory: rootDirectory,
            recordProvider: recordProvider,
            destination: destination
        )
        lastSuccessfulSyncAt = nil
        lastStagedMetrics = nil
        lastStagedBackfillStart = nil
        lastStagedExportContractRevision = nil
        Self.clearPersistedResetMetadata()
    }

    static func clearPersistedResetMetadata(
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: "sync.lastSuccessful")
        defaults.removeObject(forKey: Self.stagedMetricsKey)
        defaults.removeObject(
            forKey: Self.stagedBackfillStartKey
        )
        defaults.removeObject(
            forKey: Self.stagedExportContractRevisionKey
        )
    }

    private func stage(dates: Set<LocalDate>) async throws -> SyncReport {
        try await runtime.store.recover()
        var report = SyncReport()
        for date in dates.sorted() {
            let record = try await recordProvider.record(for: date)
            switch try await runtime.store.stageDaily(record) {
            case .staged:
                report.stagedDailyCount += 1
            case .unchanged:
                report.unchangedDailyCount += 1
            }
        }
        report.pendingUploadCount = try await runtime.store.pendingUploadCount()
        return report
    }

    private func outcome(report: SyncReport) async throws -> LiveSyncOutcome {
        if report.manifestUploaded {
            lastSuccessfulSyncAt = .now
            UserDefaults.standard.set(
                lastSuccessfulSyncAt,
                forKey: "sync.lastSuccessful"
            )
        }
        let summary = try await summary()
        await diagnostics.record(
            category: "sync",
            event: "core-report",
            fields: [
                "failedCount": String(report.failures.count),
                "failureCodes": report.failures
                    .map(\.code)
                    .sorted()
                    .joined(separator: ","),
                "pendingCount": String(report.pendingUploadCount),
                "stagedCount": String(report.stagedDailyCount),
                "unchangedCount": String(report.unchangedDailyCount),
                "uploadedCount": String(report.uploadedDailyCount),
            ]
        )
        return LiveSyncOutcome(report: report, summary: summary)
    }

    private func missingBackfillDates(
        from startDate: LocalDate,
        calendar: Calendar
    ) async throws -> Set<LocalDate> {
        let existingDates = Set(
            try await runtime.store.allDailyRecords().map(\.date)
        )
        return try BackfillDatePlanner.missingDates(
            from: startDate,
            through: .now,
            excluding: existingDates,
            calendar: calendar
        )
    }

    private func localDates(from values: Set<String>) throws -> Set<LocalDate> {
        try Set(values.map(LocalDate.init(rawValue:)))
    }

    static func effectiveHistoryStart(
        requestedStart: Date,
        existingRecordDates _: [LocalDate]
    ) -> Date {
        // Older artifacts can remain repair targets after a range is narrowed,
        // but they must never widen R4's active VO2 carry-forward window.
        requestedStart
    }

    private func merge(_ source: SyncReport, into destination: inout SyncReport) {
        destination.stagedDailyCount += source.stagedDailyCount
        destination.unchangedDailyCount += source.unchangedDailyCount
        destination.uploadedDailyCount += source.uploadedDailyCount
        destination.manifestUploaded =
            destination.manifestUploaded || source.manifestUploaded
        destination.failures.append(contentsOf: source.failures)
        destination.pendingUploadCount = source.pendingUploadCount
    }

    private func persistStagedMetrics(_ metrics: Set<HealthMetric>) {
        lastStagedMetrics = metrics
        UserDefaults.standard.set(
            metrics.map(\.rawValue).sorted(),
            forKey: Self.stagedMetricsKey
        )
    }

    private func persistStagedBackfillStart(_ date: LocalDate) {
        lastStagedBackfillStart = date
        UserDefaults.standard.set(
            date.rawValue,
            forKey: Self.stagedBackfillStartKey
        )
    }

    private func persistStagedExportContractRevision() {
        lastStagedExportContractRevision = Self.exportContractRevision
        UserDefaults.standard.set(
            Self.exportContractRevision,
            forKey: Self.stagedExportContractRevisionKey
        )
    }

    private func acquireOperation() async {
        if !operationInProgress {
            operationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationInProgress = false
            return
        }
        operationWaiters.removeFirst().resume()
    }

    private static func makeRuntime(
        rootDirectory: URL,
        recordProvider: HealthKitDailyRecordProvider,
        destination: DriveArtifactDestination
    ) throws -> Runtime {
        let store = try FileSyncStore(rootDirectory: rootDirectory)
        let engine = SyncEngine(
            configuration: SyncEngine.Configuration(
                exporterVersion: Bundle.main.infoDictionary?[
                    "CFBundleShortVersionString"
                ] as? String ?? "1.0.0",
                manifestTimeZoneIdentifier: TimeZone.current.identifier
            ),
            recordProvider: recordProvider,
            destination: destination,
            store: store
        )
        return Runtime(store: store, engine: engine)
    }
}
