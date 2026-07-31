import Foundation
import Testing
@testable import HealthRelayCore

@Suite("Idempotent sync engine")
struct SyncEngineTests {
    @Test
    func responseLossRetriesSameDailyArtifactThenPublishesManifest() async throws {
        let fixture = try fixture(
            FailedUploadFixture.self,
            named: "failed-upload"
        )
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let provider = TestRecordProvider(records: [record])
        let destination = TestDestination()
        await destination.setFailureMode(
            .transientAfterWriteOnce,
            for: .daily(record.date)
        )
        let clock = TestClock(
            try ISO8601Timestamp(rawValue: "2026-07-23T18:10:00+03:00").date()
        )
        let store = try FileSyncStore(rootDirectory: directory)
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul",
                retryPolicy: RetryPolicy(
                    initialDelay: 10,
                    maximumDelay: 100,
                    jitterRatio: 0
                )
            ),
            recordProvider: provider,
            destination: destination,
            store: store,
            clock: clock,
            jitterSource: FixedJitterSource(value: 0.5)
        )

        let first = try await engine.reconcile(dates: [record.date])
        #expect(first.stagedDailyCount == 1)
        #expect(first.failures.count == 1)
        #expect(!first.manifestUploaded)
        #expect(first.pendingUploadCount == 1)
        #expect(await destination.fileCount() == 1)

        let deferred = try await engine.retryPendingUploads()
        #expect(deferred.uploadedDailyCount == 0)
        #expect(deferred.pendingUploadCount == 1)
        #expect(await destination.callCount(for: .daily(record.date)) == 1)

        let retry = try await engine.retryPendingUploads(force: true)
        #expect(retry.uploadedDailyCount == 1)
        #expect(
            retry.manifestUploaded
                == fixture.expected.manifestAfterDailySuccess
        )
        #expect(retry.failures.isEmpty)
        #expect(
            retry.pendingUploadCount
                == fixture.expected.pendingUploadCount
        )
        #expect(
            await destination.fileCount()
                == fixture.expected.dailyFileCount + 1
        )
        #expect(await destination.callCount(for: .daily(record.date)) == 2)
        #expect(await destination.contains(.manifest))
        #expect(fixture.events.contains("retry-upserts-same-artifact"))
    }

    @Test
    func manifestRetryPublishesTheActualRetryTime() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let clock = TestClock(initialTime)
        let destination = TestDestination()
        await destination.setFailureMode(
            .transientAfterWriteOnce,
            for: .manifest
        )
        let harness = try makeManifestRetryHarness(
            directory: directory,
            clock: clock,
            destination: destination
        )

        let first = try await harness.engine.reconcile(
            dates: [harness.record.date]
        )
        #expect(first.failures.count == 1)
        await clock.advance(by: 10)
        let retryTime = initialTime.addingTimeInterval(10)

        let retry = try await harness.engine.retryPendingUploads()
        let uploadedData = try #require(
            await destination.contents(for: .manifest)
        )
        let manifest = try ExportManifestCodec.decode(uploadedData)

        #expect(retry.manifestUploaded)
        #expect(retry.failures.isEmpty)
        #expect(
            manifest.lastSuccessfulSyncAt
                == (try manifestTimestamp(at: retryTime))
        )
    }

    @Test
    func deferredManifestRetryDoesNotRewriteOrUpload() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let clock = TestClock(initialTime)
        let destination = TestDestination()
        await destination.setFailureMode(
            .transientAfterWriteOnce,
            for: .manifest
        )
        let harness = try makeManifestRetryHarness(
            directory: directory,
            clock: clock,
            destination: destination
        )
        _ = try await harness.engine.reconcile(
            dates: [harness.record.date]
        )
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let contentsBefore = try Data(contentsOf: manifestURL)
        let retryBefore = try await harness.store.retryItems()
        await clock.advance(by: 9)

        let retry = try await harness.engine.retryPendingUploads()

        #expect(!retry.manifestUploaded)
        #expect(retry.failures.isEmpty)
        #expect(await destination.callCount(for: .manifest) == 1)
        #expect(try Data(contentsOf: manifestURL) == contentsBefore)
        #expect(try await harness.store.retryItems() == retryBefore)
    }

    @Test
    func forcedManifestRetryPublishesFreshMetadataImmediately() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let clock = TestClock(initialTime)
        let destination = TestDestination()
        await destination.setFailureMode(
            .transientAfterWriteOnce,
            for: .manifest
        )
        let harness = try makeManifestRetryHarness(
            directory: directory,
            clock: clock,
            destination: destination
        )
        _ = try await harness.engine.reconcile(
            dates: [harness.record.date]
        )
        await clock.advance(by: 1)
        let retryTime = initialTime.addingTimeInterval(1)

        let retry = try await harness.engine.retryPendingUploads(force: true)
        let uploadedData = try #require(
            await destination.contents(for: .manifest)
        )
        let manifest = try ExportManifestCodec.decode(uploadedData)

        #expect(retry.manifestUploaded)
        #expect(await destination.callCount(for: .manifest) == 2)
        #expect(
            manifest.lastSuccessfulSyncAt
                == (try manifestTimestamp(at: retryTime))
        )
    }

    @Test
    func failedManifestRefreshContinuesRetryBackoff() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let clock = TestClock(initialTime)
        let destination = RepeatedManifestFailureDestination(
            failureCount: 2
        )
        let harness = try makeManifestRetryHarness(
            directory: directory,
            clock: clock,
            destination: destination
        )

        _ = try await harness.engine.reconcile(
            dates: [harness.record.date]
        )
        let firstRetry = try #require(
            try await harness.store.retryItems().first {
                $0.artifactID == .manifest
            }
        )
        await clock.advance(by: 10)
        let retryTime = initialTime.addingTimeInterval(10)

        let second = try await harness.engine.retryPendingUploads()
        let secondRetry = try #require(
            try await harness.store.retryItems().first {
                $0.artifactID == .manifest
            }
        )
        let attempts = await destination.manifestAttempts()
        let refreshedManifest = try ExportManifestCodec.decode(
            try #require(attempts.last)
        )

        #expect(second.failures.count == 1)
        #expect(firstRetry.attemptCount == 1)
        #expect(secondRetry.revision == firstRetry.revision)
        #expect(secondRetry.attemptCount == 2)
        #expect(
            secondRetry.notBefore
                == retryTime.addingTimeInterval(20)
        )
        #expect(
            refreshedManifest.lastSuccessfulSyncAt
                == (try manifestTimestamp(at: retryTime))
        )
    }

    @Test
    func unchangedReconcileDoesNotUploadDailyFileAgain() async throws {
        let fixture = try fixture(
            IdempotentSyncFixture.self,
            named: "idempotent-sync"
        )
        let firstSync = try #require(fixture.syncs.first)
        let secondSync = try #require(fixture.syncs.last)
        #expect(firstSync.semanticRevision == secondSync.semanticRevision)
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord(
            date: firstSync.date,
            generatedAt: firstSync.generatedAt
        )
        let provider = TestRecordProvider(records: [record])
        let destination = TestDestination()
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let store = try FileSyncStore(rootDirectory: directory)
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: provider,
            destination: destination,
            store: store,
            clock: clock,
            jitterSource: FixedJitterSource(value: 0.5)
        )

        let first = try await engine.reconcile(dates: [record.date])
        #expect(first.manifestUploaded)

        var regenerated = record
        regenerated.generatedAt = try ISO8601Timestamp(
            rawValue: secondSync.generatedAt
        )
        await provider.set(regenerated)
        await clock.advance(by: 60)
        let second = try await engine.reconcile(dates: [record.date])

        #expect(second.stagedDailyCount == 0)
        #expect(second.unchangedDailyCount == 1)
        #expect(
            await destination.callCount(for: .daily(record.date))
                == fixture.expected.dailyUploadCount
        )
        #expect(await destination.callCount(for: .manifest) == 2)
        #expect(
            await destination.fileCount()
                == fixture.expected.dailyFileCount + 1
        )
    }

    @Test
    func destinationSwitchPublishesFullSnapshotAndFreshManifest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = [
            try makeRecord(date: "2026-07-22"),
            try makeRecord(date: "2026-07-23"),
        ]
        let provider = TestRecordProvider(records: records)
        let firstDestination = TestDestination()
        let store = try FileSyncStore(rootDirectory: directory)
        let configuration = SyncEngine.Configuration(
            exporterVersion: "1.0.0",
            manifestTimeZoneIdentifier: "Europe/Istanbul"
        )
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let firstEngine = SyncEngine(
            configuration: configuration,
            recordProvider: provider,
            destination: firstDestination,
            store: store,
            clock: clock,
            jitterSource: FixedJitterSource(value: 0.5)
        )
        let firstReport = try await firstEngine.reconcile(
            dates: Set(records.map(\.date))
        )
        #expect(firstReport.manifestUploaded)
        #expect(await firstDestination.fileCount() == 3)

        try await store.resetRemoteUploadState()
        await clock.advance(by: 60)
        let secondDestination = TestDestination()
        let secondEngine = SyncEngine(
            configuration: configuration,
            recordProvider: provider,
            destination: secondDestination,
            store: store,
            clock: clock,
            jitterSource: FixedJitterSource(value: 0.5)
        )

        let secondReport = try await secondEngine.retryPendingUploads(force: true)

        #expect(secondReport.uploadedDailyCount == 2)
        #expect(secondReport.manifestUploaded)
        #expect(secondReport.pendingUploadCount == 0)
        #expect(await secondDestination.fileCount() == 3)
        for record in records {
            #expect(await secondDestination.contains(.daily(record.date)))
        }
        #expect(await secondDestination.contains(.manifest))
    }

    @Test
    func manifestWaitsUntilEveryDailyRevisionUploads() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstRecord = try makeRecord(date: "2026-07-22")
        let secondRecord = try makeRecord(date: "2026-07-23")
        let provider = TestRecordProvider(records: [firstRecord, secondRecord])
        let destination = TestDestination()
        await destination.setFailureMode(
            .transientAfterWriteOnce,
            for: .daily(secondRecord.date)
        )
        let store = try FileSyncStore(rootDirectory: directory)
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: provider,
            destination: destination,
            store: store,
            clock: TestClock(Date(timeIntervalSince1970: 1_000)),
            jitterSource: FixedJitterSource(value: 0.5)
        )

        let first = try await engine.reconcile(
            dates: [firstRecord.date, secondRecord.date]
        )
        #expect(first.failures.count == 1)
        let hasPrematureManifest = await destination.contains(.manifest)
        #expect(!hasPrematureManifest)

        let retry = try await engine.retryPendingUploads(force: true)
        #expect(retry.manifestUploaded)
        #expect(await destination.contains(.manifest))
        #expect(await destination.fileCount() == 3)
    }

    @Test
    func authorizationFailureRemainsBlockedUntilExplicitResume() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let destination = TestDestination()
        await destination.setFailureMode(
            .reauthorization,
            for: .daily(record.date)
        )
        let store = try FileSyncStore(rootDirectory: directory)
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: TestRecordProvider(records: [record]),
            destination: destination,
            store: store,
            clock: TestClock(Date(timeIntervalSince1970: 1_000)),
            jitterSource: FixedJitterSource(value: 0.5)
        )

        let first = try await engine.reconcile(dates: [record.date])
        #expect(first.failures.first?.blocked == true)
        let passiveRetry = try await engine.retryPendingUploads(force: true)
        #expect(passiveRetry.uploadedDailyCount == 0)
        #expect(await destination.callCount(for: .daily(record.date)) == 1)

        await destination.setFailureMode(.none, for: .daily(record.date))
        let reopenedStore = try FileSyncStore(rootDirectory: directory)
        let restoredEngine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: TestRecordProvider(records: [record]),
            destination: destination,
            store: reopenedStore,
            clock: TestClock(Date(timeIntervalSince1970: 2_000)),
            jitterSource: FixedJitterSource(value: 0.5)
        )
        let resumed = try await restoredEngine.resumeAfterReauthorization()
        #expect(resumed.uploadedDailyCount == 1)
        #expect(resumed.manifestUploaded)
        #expect(resumed.pendingUploadCount == 0)
    }

    @Test
    func reauthorizationResumePreservesUnrelatedTransientBackoff() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let authorizationRecord = try makeRecord(date: "2026-07-22")
        let transientRecord = try makeRecord(date: "2026-07-23")
        let store = try FileSyncStore(rootDirectory: directory)
        _ = try await store.stageDaily(authorizationRecord)
        _ = try await store.stageDaily(transientRecord)
        let initialTime = Date(timeIntervalSince1970: 1_000)
        let artifacts = try await store.dueArtifacts(
            at: initialTime,
            includeDeferred: true
        )
        let authorizationArtifact = try #require(
            artifacts.first {
                $0.id == .daily(authorizationRecord.date)
            }
        )
        let transientArtifact = try #require(
            artifacts.first {
                $0.id == .daily(transientRecord.date)
            }
        )
        let retryPolicy = RetryPolicy(
            initialDelay: 100,
            maximumDelay: 100,
            jitterRatio: 0
        )
        try await store.markFailed(
            authorizationArtifact,
            error: .reauthorizationRequired(code: "401"),
            now: initialTime,
            randomUnit: 0.5,
            retryPolicy: retryPolicy
        )
        try await store.markFailed(
            transientArtifact,
            error: .transient(code: "timedOut"),
            now: initialTime,
            randomUnit: 0.5,
            retryPolicy: retryPolicy
        )

        let clock = TestClock(
            initialTime.addingTimeInterval(50)
        )
        let destination = TestDestination()
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul",
                retryPolicy: retryPolicy
            ),
            recordProvider: TestRecordProvider(
                records: [authorizationRecord, transientRecord]
            ),
            destination: destination,
            store: store,
            clock: clock,
            jitterSource: FixedJitterSource(value: 0.5)
        )

        let report = try await engine.resumeAfterReauthorization()

        #expect(report.uploadedDailyCount == 1)
        #expect(report.pendingUploadCount == 1)
        #expect(
            await destination.callCount(
                for: .daily(authorizationRecord.date)
            ) == 1
        )
        #expect(
            await destination.callCount(
                for: .daily(transientRecord.date)
            ) == 0
        )
    }

    @Test
    func cancellationDuringResumeClockLeavesAuthorizationBlocked() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let store = try FileSyncStore(rootDirectory: directory)
        _ = try await store.stageDaily(record)
        let artifact = try #require(
            try await store.dueArtifacts(
                at: Date(),
                includeDeferred: true
            ).first
        )
        try await store.markFailed(
            artifact,
            error: .reauthorizationRequired(code: "401"),
            now: Date(timeIntervalSince1970: 1_000),
            randomUnit: 0.5,
            retryPolicy: RetryPolicy()
        )
        let clock = PausingClock(
            value: Date(timeIntervalSince1970: 2_000),
            pauseAtRequest: 1
        )
        let destination = TestDestination()
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: TestRecordProvider(records: [record]),
            destination: destination,
            store: store,
            clock: clock,
            jitterSource: FixedJitterSource(value: 0.5)
        )
        let resumeTask = Task {
            try await engine.resumeAfterReauthorization()
        }

        await clock.waitUntilRequested()
        resumeTask.cancel()
        await clock.resume()

        do {
            _ = try await resumeTask.value
            Issue.record("Expected cancellation during resume clock to propagate.")
        } catch is CancellationError {}

        let retryItem = try #require(try await store.retryItems().first)
        #expect(retryItem.blockReason == .reauthorizationRequired)
        #expect(
            await destination.callCount(for: .daily(record.date)) == 0
        )
    }

    @Test
    func retryDelayStartsWhenTheUploadActuallyFails() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let store = try FileSyncStore(rootDirectory: directory)
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul",
                retryPolicy: RetryPolicy(
                    initialDelay: 10,
                    maximumDelay: 10,
                    jitterRatio: 0
                )
            ),
            recordProvider: TestRecordProvider(records: [record]),
            destination: AdvancingFailureDestination(
                clock: clock,
                delay: 120
            ),
            store: store,
            clock: clock,
            jitterSource: AdvancingJitterSource(
                clock: clock,
                delay: 120,
                value: 0.5
            )
        )

        let report = try await engine.reconcile(dates: [record.date])
        let retryItem = try #require(try await store.retryItems().first)

        #expect(report.failures.count == 1)
        #expect(
            retryItem.notBefore
                == Date(timeIntervalSince1970: 1_130)
        )
    }

    @Test
    func cancellationLeavesTheArtifactImmediatelyRetryable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let store = try FileSyncStore(rootDirectory: directory)
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: TestRecordProvider(records: [record]),
            destination: CancellationDestination(),
            store: store,
            clock: TestClock(Date(timeIntervalSince1970: 1_000)),
            jitterSource: FixedJitterSource(value: 0.5)
        )

        do {
            _ = try await engine.reconcile(dates: [record.date])
            Issue.record("Expected cancellation to propagate.")
        } catch is CancellationError {}

        let retryItem = try #require(try await store.retryItems().first)
        #expect(retryItem.attemptCount == 0)
        #expect(retryItem.notBefore == Date(timeIntervalSince1970: 0))
        #expect(retryItem.lastErrorCode == nil)
        #expect(retryItem.blockReason == nil)
    }

    @Test
    func cancellationBeforeDueUploadDoesNotStartRemoteWork() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let provider = PausingRecordProvider(record: record)
        let destination = TestDestination()
        let store = try FileSyncStore(rootDirectory: directory)
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: provider,
            destination: destination,
            store: store,
            clock: TestClock(Date(timeIntervalSince1970: 1_000)),
            jitterSource: FixedJitterSource(value: 0.5)
        )
        let syncTask = Task {
            try await engine.reconcile(dates: [record.date])
        }

        await provider.waitUntilRequested()
        syncTask.cancel()
        await provider.resume()

        do {
            _ = try await syncTask.value
            Issue.record("Expected cancellation before upload to propagate.")
        } catch is CancellationError {}

        #expect(
            await destination.callCount(for: .daily(record.date)) == 0
        )
        #expect(try await store.pendingUploadCount() == 1)
    }

    @Test
    func cancellationAfterSuccessfulUpsertLeavesArtifactPending() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let store = try FileSyncStore(rootDirectory: directory)
        let destination = PausingSuccessfulDestination()
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: TestRecordProvider(records: [record]),
            destination: destination,
            store: store,
            clock: TestClock(Date(timeIntervalSince1970: 1_000)),
            jitterSource: FixedJitterSource(value: 0.5)
        )
        let syncTask = Task {
            try await engine.reconcile(dates: [record.date])
        }

        await destination.waitUntilUpserted()
        syncTask.cancel()
        await destination.resume()

        do {
            _ = try await syncTask.value
            Issue.record("Expected cancellation after upsert to propagate.")
        } catch is CancellationError {}

        #expect(await destination.contains(.daily(record.date)))
        let revisions = try #require(
            try await store.artifactState(for: .daily(record.date))
        )
        #expect(revisions.localRevision == 1)
        #expect(revisions.uploadedRevision == 0)
        let retryItem = try #require(try await store.retryItems().first)
        #expect(retryItem.artifactID == .daily(record.date))
        #expect(retryItem.attemptCount == 0)
    }

    @Test
    func cancellationDuringJitterLeavesFailureStateUntouched() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let store = try FileSyncStore(rootDirectory: directory)
        let jitterSource = PausingJitterSource()
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: TestRecordProvider(records: [record]),
            destination: TransientFailureDestination(),
            store: store,
            clock: TestClock(Date(timeIntervalSince1970: 1_000)),
            jitterSource: jitterSource
        )
        let syncTask = Task {
            try await engine.reconcile(dates: [record.date])
        }

        await jitterSource.waitUntilRequested()
        syncTask.cancel()
        await jitterSource.resume(returning: 0.5)

        do {
            _ = try await syncTask.value
            Issue.record("Expected cancellation during jitter to propagate.")
        } catch is CancellationError {}

        let retryItem = try #require(try await store.retryItems().first)
        #expect(retryItem.attemptCount == 0)
        #expect(retryItem.notBefore == Date(timeIntervalSince1970: 0))
        #expect(retryItem.lastErrorCode == nil)
        #expect(retryItem.blockReason == nil)
    }

    @Test
    func cancellationDuringFailureTimestampLeavesFailureStateUntouched() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try makeRecord()
        let store = try FileSyncStore(rootDirectory: directory)
        let clock = PausingClock(
            value: Date(timeIntervalSince1970: 1_000),
            pauseAtRequest: 2
        )
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: TestRecordProvider(records: [record]),
            destination: TransientFailureDestination(),
            store: store,
            clock: clock,
            jitterSource: FixedJitterSource(value: 0.5)
        )
        let syncTask = Task {
            try await engine.reconcile(dates: [record.date])
        }

        await clock.waitUntilRequested()
        syncTask.cancel()
        await clock.resume()

        do {
            _ = try await syncTask.value
            Issue.record(
                "Expected cancellation during failure timestamp lookup to propagate."
            )
        } catch is CancellationError {}

        let retryItem = try #require(try await store.retryItems().first)
        #expect(retryItem.attemptCount == 0)
        #expect(retryItem.notBefore == Date(timeIntervalSince1970: 0))
        #expect(retryItem.lastErrorCode == nil)
        #expect(retryItem.blockReason == nil)
    }

    @Test
    func retryDelayCapsPositiveJitterAtMaximum() {
        let policy = RetryPolicy(
            initialDelay: 10,
            maximumDelay: 40,
            jitterRatio: 0.5
        )

        #expect(policy.delay(afterFailure: 1, randomUnit: 1) == 15)
        #expect(policy.delay(afterFailure: 10, randomUnit: 1) == 40)
    }

    @Test
    func thirtyDayBackfillUploadsAnEmptyRecordForEveryDay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try (0..<30).map { offset in
            try makeRecord(
                date: String(format: "2026-06-%02d", offset + 1),
                steps: nil
            )
        }
        let provider = TestRecordProvider(records: records)
        let destination = TestDestination()
        let store = try FileSyncStore(rootDirectory: directory)
        let engine = SyncEngine(
            configuration: .init(
                exporterVersion: "1.0.0",
                manifestTimeZoneIdentifier: "Europe/Istanbul"
            ),
            recordProvider: provider,
            destination: destination,
            store: store,
            clock: TestClock(Date(timeIntervalSince1970: 1_000)),
            jitterSource: FixedJitterSource(value: 0.5)
        )

        let report = try await engine.reconcile(
            dates: Set(records.map(\.date))
        )
        let manifestData = try #require(
            await destination.contents(for: .manifest)
        )
        let manifest = try ExportManifestCodec.decode(manifestData)

        #expect(report.stagedDailyCount == 30)
        #expect(report.uploadedDailyCount == 30)
        #expect(report.manifestUploaded)
        #expect(await destination.fileCount() == 31)
        #expect(manifest.recordCount == 30)
        #expect(manifest.earliestDate == records.first?.date)
        #expect(manifest.latestDate == records.last?.date)
        for record in records {
            #expect(await destination.contains(.daily(record.date)))
        }
    }
}

private struct ManifestRetryHarness {
    let record: DailyHealthRecord
    let store: FileSyncStore
    let engine: SyncEngine
}

private func makeManifestRetryHarness(
    directory: URL,
    clock: TestClock,
    destination: any ExportArtifactDestination
) throws -> ManifestRetryHarness {
    let record = try makeRecord()
    let store = try FileSyncStore(rootDirectory: directory)
    let engine = SyncEngine(
        configuration: .init(
            exporterVersion: "1.0.0",
            manifestTimeZoneIdentifier: "Europe/Istanbul",
            retryPolicy: RetryPolicy(
                initialDelay: 10,
                maximumDelay: 100,
                jitterRatio: 0
            )
        ),
        recordProvider: TestRecordProvider(records: [record]),
        destination: destination,
        store: store,
        clock: clock,
        jitterSource: FixedJitterSource(value: 0.5)
    )
    return ManifestRetryHarness(
        record: record,
        store: store,
        engine: engine
    )
}

private func manifestTimestamp(at date: Date) throws -> ISO8601Timestamp {
    let timeZone = try #require(TimeZone(identifier: "Europe/Istanbul"))
    return try ISO8601Timestamp(date: date, timeZone: timeZone)
}

private actor RepeatedManifestFailureDestination:
    ExportArtifactDestination
{
    private var failuresRemaining: Int
    private var attempts: [Data] = []

    init(failureCount: Int) {
        failuresRemaining = failureCount
    }

    func upsert(_ artifact: ExportArtifact) async throws {
        guard artifact.id == .manifest else { return }
        attempts.append(artifact.contents)
        guard failuresRemaining > 0 else { return }
        failuresRemaining -= 1
        throw ExportDestinationError.transient(code: "timedOut")
    }

    func manifestAttempts() -> [Data] {
        attempts
    }
}

private func fixture<Value: Decodable>(
    _ type: Value.Type,
    named name: String
) throws -> Value {
    let url = try #require(
        Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        )
    )
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
}

private struct FailedUploadFixture: Decodable {
    struct Expected: Decodable {
        let dailyFileCount: Int
        let manifestAfterDailySuccess: Bool
        let pendingUploadCount: Int
    }

    let events: [String]
    let expected: Expected
}

private struct IdempotentSyncFixture: Decodable {
    struct Sync: Decodable {
        let date: String
        let semanticRevision: Int
        let generatedAt: String
    }

    struct Expected: Decodable {
        let dailyFileCount: Int
        let dailyUploadCount: Int
    }

    let syncs: [Sync]
    let expected: Expected
}

private struct AdvancingFailureDestination: ExportArtifactDestination {
    let clock: TestClock
    let delay: TimeInterval

    func upsert(_ artifact: ExportArtifact) async throws {
        await clock.advance(by: delay)
        throw ExportDestinationError.transient(code: "timedOut")
    }
}

private struct AdvancingJitterSource: RetryJitterSource {
    let clock: TestClock
    let delay: TimeInterval
    let value: Double

    func nextUnitIntervalValue() async -> Double {
        await clock.advance(by: delay)
        return value
    }
}

private struct CancellationDestination: ExportArtifactDestination {
    func upsert(_ artifact: ExportArtifact) async throws {
        throw CancellationError()
    }
}

private actor PausingRecordProvider: DailyRecordProvider {
    private let record: DailyHealthRecord
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var recordContinuation:
        CheckedContinuation<DailyHealthRecord, any Error>?

    init(record: DailyHealthRecord) {
        self.record = record
    }

    func record(for date: LocalDate) async throws -> DailyHealthRecord {
        guard date == record.date else {
            throw TestError.missingRecord
        }
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return try await withCheckedThrowingContinuation { continuation in
            recordContinuation = continuation
        }
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resume() {
        let continuation = recordContinuation
        recordContinuation = nil
        continuation?.resume(returning: record)
    }
}

private struct TransientFailureDestination: ExportArtifactDestination {
    func upsert(_ artifact: ExportArtifact) async throws {
        throw ExportDestinationError.transient(code: "timedOut")
    }
}

private actor PausingSuccessfulDestination: ExportArtifactDestination {
    private var files: [ExportArtifactID: Data] = [:]
    private var upserted = false
    private var upsertWaiters: [CheckedContinuation<Void, Never>] = []
    private var returnContinuation: CheckedContinuation<Void, Never>?

    func upsert(_ artifact: ExportArtifact) async throws {
        files[artifact.id] = artifact.contents
        upserted = true
        let waiters = upsertWaiters
        upsertWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            returnContinuation = continuation
        }
    }

    func waitUntilUpserted() async {
        guard !upserted else { return }
        await withCheckedContinuation { continuation in
            upsertWaiters.append(continuation)
        }
    }

    func resume() {
        let continuation = returnContinuation
        returnContinuation = nil
        continuation?.resume()
    }

    func contains(_ id: ExportArtifactID) -> Bool {
        files[id] != nil
    }
}

private actor PausingJitterSource: RetryJitterSource {
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var valueContinuation: CheckedContinuation<Double, Never>?

    func nextUnitIntervalValue() async -> Double {
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return await withCheckedContinuation { continuation in
            valueContinuation = continuation
        }
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resume(returning value: Double) {
        let continuation = valueContinuation
        valueContinuation = nil
        continuation?.resume(returning: value)
    }
}

private actor PausingClock: SyncClock {
    private let value: Date
    private let pauseAtRequest: Int
    private var requestCount = 0
    private var requested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var valueContinuation: CheckedContinuation<Date, Never>?

    init(value: Date, pauseAtRequest: Int) {
        self.value = value
        self.pauseAtRequest = pauseAtRequest
    }

    func now() async -> Date {
        requestCount += 1
        guard requestCount == pauseAtRequest else { return value }
        requested = true
        let waiters = requestWaiters
        requestWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        return await withCheckedContinuation { continuation in
            valueContinuation = continuation
        }
    }

    func waitUntilRequested() async {
        guard !requested else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resume() {
        let continuation = valueContinuation
        valueContinuation = nil
        continuation?.resume(returning: value)
    }
}
