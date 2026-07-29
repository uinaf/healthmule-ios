@preconcurrency import HealthKit
import Foundation
import HealthRelayCore
import XCTest
@testable import HealthRelay

final class LiveSyncCoordinatorTests: XCTestCase {
    func testStageFailureDoesNotCommitAnchorsOrSelectionMetadata() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.cleanUp() }
        let provider = CoordinatorRecordProvider(
            records: fixture.records,
            failureDate: fixture.dates[0]
        )
        let health = CoordinatorHealthChanges(startDate: fixture.startInstant)
        let coordinator = try fixture.makeCoordinator(
            health: health,
            provider: provider
        )

        do {
            _ = try await coordinator.reconcile(
                trigger: .manual,
                enabledMetrics: [.stepCount],
                backfillStart: fixture.dates[0]
            )
            XCTFail("Expected the staged record provider to fail.")
        } catch CoordinatorTestError.recordFailure {
            // Expected.
        }

        let committedMetrics = await health.committedMetrics()
        XCTAssertTrue(committedMetrics.isEmpty)
        XCTAssertNil(
            fixture.defaults.stringArray(
                forKey: "sync.lastStagedMetrics"
            )
        )
        XCTAssertNil(
            fixture.defaults.string(
                forKey: "sync.lastStagedBackfillStart"
            )
        )
        XCTAssertNil(
            fixture.defaults.object(
                forKey: "sync.lastStagedExportContractRevision"
            )
        )
    }

    func testEveryRequestedDateIsDurableBeforeFirstAnchorCommit() async throws {
        let fixture = try CoordinatorFixture()
        defer { fixture.cleanUp() }
        let provider = CoordinatorRecordProvider(records: fixture.records)
        let health = CoordinatorHealthChanges(
            startDate: fixture.startInstant,
            stagingRoot: fixture.rootDirectory,
            expectedStagedDates: Set(fixture.dates)
        )
        let coordinator = try fixture.makeCoordinator(
            health: health,
            provider: provider
        )

        _ = try await coordinator.reconcile(
            trigger: .manual,
            enabledMetrics: [.bodyMass, .stepCount],
            backfillStart: fixture.dates[0]
        )

        let stagedChecks = await health.stagedChecks()
        XCTAssertEqual(stagedChecks.count, 2)
        XCTAssertTrue(stagedChecks.allSatisfy(\.allDatesWereDurable))
        for date in fixture.dates {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: fixture.rootDirectory
                        .appendingPathComponent("daily", isDirectory: true)
                        .appendingPathComponent("\(date.rawValue).json")
                        .path
                )
            )
        }
    }

    func testCancelledQueuedReconcileDoesNotLoseFollowingOperation() async throws {
        let fixture = try CoordinatorFixture(dayCount: 1)
        defer { fixture.cleanUp() }
        let provider = CoordinatorRecordProvider(records: fixture.records)
        let health = CoordinatorHealthChanges(
            startDate: fixture.startInstant,
            blockFirstChange: true
        )
        let queueProbe = CoordinatorQueueProbe()
        let coordinator = try fixture.makeCoordinator(
            health: health,
            provider: provider,
            queueProbe: queueProbe
        )
        let backfillStart = fixture.dates[0]

        let first = Task {
            try await coordinator.reconcile(
                trigger: .manual,
                enabledMetrics: [.bodyMass],
                backfillStart: backfillStart
            )
        }
        await health.waitUntilFirstChangeStarts()

        let cancelled = Task {
            try await coordinator.reconcile(
                trigger: .manual,
                enabledMetrics: [.stepCount],
                backfillStart: backfillStart
            )
        }
        await queueProbe.wait(until: 1)
        let following = Task {
            try await coordinator.reconcile(
                trigger: .manual,
                enabledMetrics: [.hrvSDNN],
                backfillStart: backfillStart
            )
        }
        await queueProbe.wait(until: 2)
        cancelled.cancel()
        await health.releaseFirstChange()

        _ = try await first.value
        do {
            _ = try await cancelled.value
            XCTFail("Expected the queued reconcile to observe cancellation.")
        } catch is CancellationError {
            // Expected.
        }
        _ = try await following.value

        let changedMetrics = await health.changedMetrics()
        XCTAssertEqual(changedMetrics.first, .bodyMass)
        XCTAssertFalse(changedMetrics.contains(.stepCount))
        XCTAssertTrue(changedMetrics.contains(.hrvSDNN))
    }

    func testConcurrentReconcilesAcquireInFIFOOrder() async throws {
        let fixture = try CoordinatorFixture(dayCount: 1)
        defer { fixture.cleanUp() }
        let provider = CoordinatorRecordProvider(records: fixture.records)
        let health = CoordinatorHealthChanges(
            startDate: fixture.startInstant,
            blockFirstChange: true
        )
        let queueProbe = CoordinatorQueueProbe()
        let coordinator = try fixture.makeCoordinator(
            health: health,
            provider: provider,
            queueProbe: queueProbe
        )
        let backfillStart = fixture.dates[0]

        let first = Task {
            try await coordinator.reconcile(
                trigger: .manual,
                enabledMetrics: [.bodyMass],
                backfillStart: backfillStart
            )
        }
        await health.waitUntilFirstChangeStarts()

        let second = Task {
            try await coordinator.reconcile(
                trigger: .manual,
                enabledMetrics: [.stepCount],
                backfillStart: backfillStart
            )
        }
        await queueProbe.wait(until: 1)
        let third = Task {
            try await coordinator.reconcile(
                trigger: .manual,
                enabledMetrics: [.hrvSDNN],
                backfillStart: backfillStart
            )
        }
        await queueProbe.wait(until: 2)
        await health.releaseFirstChange()

        _ = try await first.value
        _ = try await second.value
        _ = try await third.value

        let changedMetrics = await health.changedMetrics()
        XCTAssertEqual(changedMetrics, [.bodyMass, .stepCount, .hrvSDNN])
    }

    func testSuccessfulPassCommitsEveryBatchBeforeFirstUpload() async throws {
        let fixture = try CoordinatorFixture(dayCount: 1)
        defer { fixture.cleanUp() }
        let events = CoordinatorEventLog()
        let provider = CoordinatorRecordProvider(records: fixture.records)
        let health = CoordinatorHealthChanges(
            startDate: fixture.startInstant,
            events: events
        )
        let destination = CoordinatorDestination(events: events)
        let coordinator = try fixture.makeCoordinator(
            health: health,
            provider: provider,
            destination: destination,
            events: events
        )

        _ = try await coordinator.reconcile(
            trigger: .manual,
            enabledMetrics: [.bodyMass, .stepCount],
            backfillStart: fixture.dates[0]
        )

        let recordedEvents = await events.snapshot()
        let stageIndexes = recordedEvents.indices.filter {
            if case .stage = recordedEvents[$0] {
                return true
            }
            return false
        }
        let commitIndexes = recordedEvents.indices.filter {
            if case .commit = recordedEvents[$0] {
                return true
            }
            return false
        }
        let firstUploadIndex = try XCTUnwrap(
            recordedEvents.firstIndex {
                if case .upload = $0 {
                    return true
                }
                return false
            }
        )
        let lastStageIndex = try XCTUnwrap(stageIndexes.last)
        XCTAssertEqual(stageIndexes.count, fixture.dates.count)
        XCTAssertEqual(commitIndexes.count, 2)
        XCTAssertTrue(
            commitIndexes.allSatisfy {
                lastStageIndex < $0 && $0 < firstUploadIndex
            }
        )
    }
}

private struct CoordinatorFixture {
    let rootDirectory: URL
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let calendar: Calendar
    let now: Date
    let dates: [LocalDate]
    let records: [LocalDate: DailyHealthRecord]
    let startInstant: Date

    init(dayCount: Int = 3) throws {
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "LiveSyncCoordinatorTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defaultsSuiteName = "LiveSyncCoordinatorTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(
            UserDefaults(suiteName: defaultsSuiteName)
        )
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.locale = Locale(identifier: "en_US_POSIX")
        utcCalendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        calendar = utcCalendar
        let fixedNow = try XCTUnwrap(
            utcCalendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 29,
                    hour: 12
                )
            )
        )
        now = fixedNow
        let createdDates = try (0..<dayCount).reversed().map { offset in
            let instant = try XCTUnwrap(
                utcCalendar.date(
                    byAdding: .day,
                    value: -offset,
                    to: fixedNow
                )
            )
            let components = utcCalendar.dateComponents(
                [.year, .month, .day],
                from: instant
            )
            return try LocalDate(
                year: try XCTUnwrap(components.year),
                month: try XCTUnwrap(components.month),
                day: try XCTUnwrap(components.day)
            )
        }
        dates = createdDates
        let createdRecords = try Dictionary(
            uniqueKeysWithValues: createdDates.map { date in
                (
                    date,
                    DailyHealthRecord(
                        date: date,
                        timeZone: "UTC",
                        generatedAt: try ISO8601Timestamp(
                            date: fixedNow,
                            timeZone: utcCalendar.timeZone
                        ),
                        metrics: DailyHealthMetrics(steps: 1),
                        workouts: [],
                        totals: WorkoutTotals(
                            workoutMinutes: 0,
                            workoutActiveEnergyKcal: 0
                        ),
                        sources: HealthRecordSources(
                            deviceNames: [],
                            sampleCount: 0
                        )
                    )
                )
            }
        )
        records = createdRecords
        startInstant = try XCTUnwrap(
            utcCalendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 29 - (dayCount - 1)
                )
            )
        )
    }

    func makeCoordinator(
        health: CoordinatorHealthChanges,
        provider: CoordinatorRecordProvider,
        destination: CoordinatorDestination = CoordinatorDestination(),
        queueProbe: CoordinatorQueueProbe? = nil,
        events: CoordinatorEventLog? = nil
    ) throws -> LiveSyncCoordinator {
        let fixedNow = now
        let fixedCalendar = calendar
        return try LiveSyncCoordinator(
            rootDirectory: rootDirectory,
            healthKit: health,
            recordProvider: provider,
            destination: destination,
            diagnostics: DiagnosticsRecorder(),
            defaultsSuiteName: defaultsSuiteName,
            calendar: { fixedCalendar },
            now: { fixedNow },
            operationQueued: { waiterCount in
                queueProbe?.record(waiterCount)
            },
            recordStaged: { date in
                await events?.append(.stage(date))
            }
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: rootDirectory)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }
}

private final class CoordinatorQueueProbe: @unchecked Sendable {
    private struct Waiter {
        let minimumCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var latestCount = 0
    private var waiters: [Waiter] = []

    func record(_ waiterCount: Int) {
        lock.lock()
        latestCount = max(latestCount, waiterCount)
        let ready = waiters.filter {
            latestCount >= $0.minimumCount
        }
        waiters.removeAll {
            latestCount >= $0.minimumCount
        }
        lock.unlock()

        for waiter in ready {
            waiter.continuation.resume()
        }
    }

    func wait(until minimumCount: Int) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if latestCount >= minimumCount {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters.append(
                Waiter(
                    minimumCount: minimumCount,
                    continuation: continuation
                )
            )
            lock.unlock()
        }
    }
}

private actor CoordinatorRecordProvider: ConfigurableDailyRecordProvider {
    private let records: [LocalDate: DailyHealthRecord]
    private let failureDate: LocalDate?

    init(
        records: [LocalDate: DailyHealthRecord],
        failureDate: LocalDate? = nil
    ) {
        self.records = records
        self.failureDate = failureDate
    }

    func configure(
        earliestVO2Date _: Date,
        enabledMetrics _: Set<HealthMetric>
    ) {}

    func record(for date: LocalDate) async throws -> DailyHealthRecord {
        if date == failureDate {
            throw CoordinatorTestError.recordFailure
        }
        guard let record = records[date] else {
            throw CoordinatorTestError.missingRecord(date.rawValue)
        }
        return record
    }
}

private actor CoordinatorHealthChanges: HealthChangeTracking {
    struct StagedCheck: Sendable {
        let metric: HealthMetric
        let allDatesWereDurable: Bool
    }

    private let queryStart: Date
    private let stagingRoot: URL?
    private let expectedStagedDates: Set<LocalDate>
    private let events: CoordinatorEventLog?
    private var commits: [HealthMetric] = []
    private var changes: [HealthMetric] = []
    private var checks: [StagedCheck] = []
    private var shouldBlockFirstChange: Bool
    private var firstChangeStarted = false
    private var firstChangeStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstChangeContinuation: CheckedContinuation<Void, Never>?

    init(
        startDate: Date,
        stagingRoot: URL? = nil,
        expectedStagedDates: Set<LocalDate> = [],
        events: CoordinatorEventLog? = nil,
        blockFirstChange: Bool = false
    ) {
        queryStart = startDate
        self.stagingRoot = stagingRoot
        self.expectedStagedDates = expectedStagedDates
        self.events = events
        shouldBlockFirstChange = blockFirstChange
    }

    func startDate(for _: LocalDate) async throws -> Date {
        queryStart
    }

    func changedDates(
        for metric: HealthMetric,
        calendar _: Calendar,
        notBefore _: Date
    ) async throws -> HealthAnchoredChangeBatch {
        changes.append(metric)
        if shouldBlockFirstChange {
            shouldBlockFirstChange = false
            firstChangeStarted = true
            let waiters = firstChangeStartWaiters
            firstChangeStartWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                firstChangeContinuation = continuation
            }
        }
        return HealthAnchoredChangeBatch(
            metric: metric,
            affectedDates: [],
            anchor: HKQueryAnchor(fromValue: changes.count),
            queryStart: queryStart,
            sampleDates: [:],
            deletedUUIDs: []
        )
    }

    func commit(_ batch: HealthAnchoredChangeBatch) async throws {
        commits.append(batch.metric)
        if let stagingRoot {
            let allDatesWereDurable = expectedStagedDates.allSatisfy { date in
                FileManager.default.fileExists(
                    atPath: stagingRoot
                        .appendingPathComponent("daily", isDirectory: true)
                        .appendingPathComponent("\(date.rawValue).json")
                        .path
                )
            }
            checks.append(
                StagedCheck(
                    metric: batch.metric,
                    allDatesWereDurable: allDatesWereDurable
                )
            )
        }
        await events?.append(.commit(batch.metric))
    }

    func resetAnchors() async {}

    func waitUntilFirstChangeStarts() async {
        if firstChangeStarted {
            return
        }
        await withCheckedContinuation { continuation in
            firstChangeStartWaiters.append(continuation)
        }
    }

    func releaseFirstChange() {
        firstChangeContinuation?.resume()
        firstChangeContinuation = nil
    }

    func committedMetrics() -> [HealthMetric] {
        commits
    }

    func changedMetrics() -> [HealthMetric] {
        changes
    }

    func stagedChecks() -> [StagedCheck] {
        checks
    }
}

private actor CoordinatorDestination: ExportArtifactDestination {
    private let events: CoordinatorEventLog?

    init(events: CoordinatorEventLog? = nil) {
        self.events = events
    }

    func upsert(_ artifact: ExportArtifact) async throws {
        await events?.append(.upload(artifact.id))
    }
}

private actor CoordinatorEventLog {
    enum Event: Equatable, Sendable {
        case stage(LocalDate)
        case commit(HealthMetric)
        case upload(ExportArtifactID)
    }

    private var events: [Event] = []

    func append(_ event: Event) {
        events.append(event)
    }

    func snapshot() -> [Event] {
        events
    }
}

private enum CoordinatorTestError: Error {
    case recordFailure
    case missingRecord(String)
}
