import Foundation

public actor SyncEngine {
    public struct Configuration: Equatable, Sendable {
        public var exporterVersion: String
        public var manifestTimeZoneIdentifier: String
        public var retryPolicy: RetryPolicy

        public init(
            exporterVersion: String,
            manifestTimeZoneIdentifier: String,
            retryPolicy: RetryPolicy = RetryPolicy()
        ) {
            self.exporterVersion = exporterVersion
            self.manifestTimeZoneIdentifier = manifestTimeZoneIdentifier
            self.retryPolicy = retryPolicy
        }
    }

    private let configuration: Configuration
    private let recordProvider: any DailyRecordProvider
    private let destination: any ExportArtifactDestination
    private let store: FileSyncStore
    private let clock: any SyncClock
    private let jitterSource: any RetryJitterSource

    public init(
        configuration: Configuration,
        recordProvider: any DailyRecordProvider,
        destination: any ExportArtifactDestination,
        store: FileSyncStore,
        clock: any SyncClock = SystemSyncClock(),
        jitterSource: any RetryJitterSource = SystemRetryJitterSource()
    ) {
        self.configuration = configuration
        self.recordProvider = recordProvider
        self.destination = destination
        self.store = store
        self.clock = clock
        self.jitterSource = jitterSource
    }

    public func reconcile(dates: Set<LocalDate>) async throws -> SyncReport {
        try await store.recover()
        var report = SyncReport()

        for date in dates.sorted() {
            let record = try await recordProvider.record(for: date)
            guard record.date == date else {
                throw FileSyncStoreError.invalidArtifact(
                    "Provider returned \(record.date.rawValue) for \(date.rawValue)."
                )
            }
            switch try await store.stageDaily(record) {
            case .staged:
                report.stagedDailyCount += 1
            case .unchanged:
                report.unchangedDailyCount += 1
            }
        }

        let uploadResult = try await uploadPending(includeDeferred: false)
        report.uploadedDailyCount += uploadResult.uploadedDailyCount
        report.manifestUploaded = uploadResult.manifestUploaded
        report.failures.append(contentsOf: uploadResult.failures)

        if
            try await store.allDailyUploadsAreCurrent(),
            !(try await store.hasPendingManifestUpload()),
            report.failures.isEmpty
        {
            let manifestResult = try await stageAndUploadManifest()
            report.manifestUploaded = report.manifestUploaded || manifestResult.manifestUploaded
            report.failures.append(contentsOf: manifestResult.failures)
        }

        report.pendingUploadCount = try await store.pendingUploadCount()
        return report
    }

    public func retryPendingUploads(force: Bool = false) async throws -> SyncReport {
        try await store.recover()
        var report = try await uploadPending(includeDeferred: force)

        if
            try await store.allDailyUploadsAreCurrent(),
            try await store.manifestRequiresRefresh(),
            report.failures.isEmpty
        {
            let manifestResult = try await stageAndUploadManifest()
            report.manifestUploaded = report.manifestUploaded || manifestResult.manifestUploaded
            report.failures.append(contentsOf: manifestResult.failures)
        }

        report.pendingUploadCount = try await store.pendingUploadCount()
        return report
    }

    public func resumeAfterReauthorization() async throws -> SyncReport {
        let now = await clock.now()
        try Task.checkCancellation()
        _ = try await store.unblockReauthorizationFailures(at: now)
        try Task.checkCancellation()
        return try await retryPendingUploads()
    }

    private func stageAndUploadManifest() async throws -> SyncReport {
        let records = try await store.allDailyRecords()
        guard
            let earliest = records.map(\.date).min(),
            let latest = records.map(\.date).max()
        else {
            return SyncReport()
        }
        guard let timeZone = TimeZone(identifier: configuration.manifestTimeZoneIdentifier) else {
            throw SchemaValidationError.invalidTimeZone(
                configuration.manifestTimeZoneIdentifier
            )
        }

        let now = await clock.now()
        let manifest = ExportManifest(
            exporterVersion: configuration.exporterVersion,
            timeZone: configuration.manifestTimeZoneIdentifier,
            lastSuccessfulSyncAt: try ISO8601Timestamp(
                date: now,
                timeZone: timeZone
            ),
            earliestDate: earliest,
            latestDate: latest,
            recordCount: records.count
        )
        _ = try await store.stageManifest(manifest)
        return try await uploadPending(includeDeferred: false)
    }

    private func uploadPending(includeDeferred: Bool) async throws -> SyncReport {
        var report = SyncReport()
        let now = await clock.now()
        let artifacts = try await store.dueArtifacts(
            at: now,
            includeDeferred: includeDeferred
        )
        try Task.checkCancellation()

        for artifact in artifacts {
            try Task.checkCancellation()
            do {
                try await destination.upsert(artifact)
                try Task.checkCancellation()
                try await store.markUploaded(artifact)
                try Task.checkCancellation()
                if artifact.id.kind == .daily {
                    report.uploadedDailyCount += 1
                } else {
                    report.manifestUploaded = true
                }
            } catch {
                if error is CancellationError {
                    throw error
                }
                try Task.checkCancellation()
                let destinationError = classify(error)
                let failureTime = await clock.now()
                try Task.checkCancellation()
                let randomUnit = await jitterSource.nextUnitIntervalValue()
                try Task.checkCancellation()
                try await store.markFailed(
                    artifact,
                    error: destinationError,
                    now: failureTime,
                    randomUnit: randomUnit,
                    retryPolicy: configuration.retryPolicy
                )
                try Task.checkCancellation()
                report.failures.append(
                    SyncFailureSummary(
                        artifactID: artifact.id,
                        code: destinationError.code,
                        blocked: destinationError.isBlocked
                    )
                )
                if artifact.id.kind == .daily {
                    break
                }
            }
        }
        report.pendingUploadCount = try await store.pendingUploadCount()
        return report
    }

    private func classify(_ error: Error) -> ExportDestinationError {
        if let error = error as? ExportDestinationError {
            return error
        }
        return .transient(code: String(describing: type(of: error)))
    }
}

private extension ExportDestinationError {
    var code: String {
        switch self {
        case let .transient(code, _),
             let .reauthorizationRequired(code),
             let .permanent(code):
            code
        }
    }

    var isBlocked: Bool {
        switch self {
        case .transient:
            false
        case .reauthorizationRequired, .permanent:
            true
        }
    }
}
