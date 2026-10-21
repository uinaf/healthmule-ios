@preconcurrency import BackgroundTasks
@preconcurrency import HealthKit
import Foundation
import HealthMuleCore
import XCTest
@testable import HealthMule

final class AppConfigurationTests: XCTestCase {
    func testReconcileOccupancyAdmitsOnceUntilReleased() {
        var occupancy = ReconcileOccupancy()
        XCTAssertTrue(occupancy.admit())
        XCTAssertFalse(occupancy.admit())
        occupancy.release()
        XCTAssertTrue(occupancy.admit())
        XCTAssertFalse(occupancy.admit())
    }

    @MainActor
    func testColdBackgroundBootstrapKeepsBackgroundAttributionExactlyOnce() {
        XCTAssertEqual(
            AppModel.preferredBootstrapTrigger(
                current: .appLaunch,
                requested: .backgroundRefresh
            ),
            .backgroundRefresh
        )
        XCTAssertFalse(
            AppModel.backgroundRefreshRequiresFollowUp(
                afterBootstrap: .backgroundRefresh
            )
        )
        XCTAssertTrue(
            AppModel.backgroundRefreshRequiresFollowUp(
                afterBootstrap: .appLaunch
            )
        )
        XCTAssertTrue(
            AppModel.backgroundRefreshRequiresFollowUp(
                afterBootstrap: nil
            )
        )
        XCTAssertFalse(
            AppModel.backgroundRefreshRequiresScheduling(
                afterBootstrap: .backgroundRefresh
            )
        )
        XCTAssertFalse(
            AppModel.backgroundRefreshRequiresScheduling(
                afterBootstrap: .appLaunch
            )
        )
        XCTAssertTrue(
            AppModel.backgroundRefreshRequiresScheduling(
                afterBootstrap: nil
            )
        )
    }

    @MainActor
    func testBackgroundRefreshSchedulingMapsPublicErrorCodes() {
        XCTAssertEqual(
            BackgroundRefreshCoordinator.scheduleFailure(
                domain: BGTaskScheduler.errorDomain,
                code: 1
            ),
            .unavailable
        )
        XCTAssertEqual(
            BackgroundRefreshCoordinator.scheduleFailure(
                domain: BGTaskScheduler.errorDomain,
                code: 2
            ),
            .tooManyPendingRequests
        )
        XCTAssertEqual(
            BackgroundRefreshCoordinator.scheduleFailure(
                domain: BGTaskScheduler.errorDomain,
                code: 3
            ),
            .notPermitted
        )
        XCTAssertEqual(
            BackgroundRefreshCoordinator.scheduleFailure(
                domain: BGTaskScheduler.errorDomain,
                code: 4
            ),
            .immediateRunIneligible
        )
        XCTAssertEqual(
            BackgroundRefreshCoordinator.scheduleFailure(
                domain: "unexpected",
                code: 1
            ),
            .unknown
        )
    }

    func testSyncTriggersClassifyOperationOrigin() {
        for trigger in [
            SyncTrigger.manual,
            .retry,
            .rebuild,
            .watchCompanion,
        ] {
            XCTAssertEqual(trigger.operationOrigin, .userInitiated)
        }
        for trigger in [
            SyncTrigger.appLaunch,
            .foreground,
            .metricSelection,
            .historySelection,
            .backgroundRefresh,
            .healthObserver,
        ] {
            XCTAssertEqual(trigger.operationOrigin, .automatic)
        }
    }

    func testPresentedOperationStateSuppressesOnlyAutomaticResults() {
        let working = OperationState.working(.sync, "Syncing")
        let results = [
            OperationState.warning(.sync, "Uploads remain pending."),
            .succeeded(.sync, "Everything is up to date."),
            .failed(.sync, "Upload failed."),
        ]

        XCTAssertEqual(working.presented(for: .automatic), working)
        for result in results {
            XCTAssertEqual(result.presented(for: .automatic), .idle)
            XCTAssertEqual(result.presented(for: .userInitiated), result)
        }
    }

    func testSyncProgressStateRejectsStaleAndFinishedCallbacks() throws {
        var state = SyncProgressState()
        let firstProgress = SyncProgress(
            phase: .staging,
            completedUnits: 1,
            totalUnits: 3,
            currentDate: try LocalDate(rawValue: "2026-07-27")
        )
        let staleProgress = SyncProgress(
            phase: .staging,
            completedUnits: 2,
            totalUnits: 3,
            currentDate: try LocalDate(rawValue: "2026-07-28")
        )

        state.begin(epoch: 10)
        state.publish(firstProgress, epoch: 10)
        XCTAssertEqual(state.progress, firstProgress)

        state.begin(epoch: 11)
        XCTAssertNil(state.progress)
        state.publish(staleProgress, epoch: 10)
        XCTAssertNil(state.progress)

        state.publish(staleProgress, epoch: 11)
        XCTAssertEqual(state.progress, staleProgress)
        state.clear()
        XCTAssertNil(state.progress)
        state.publish(staleProgress, epoch: 11)
        XCTAssertNil(state.progress)
    }

    func testBackgroundDeliveryCallbackMapping() {
        XCTAssertEqual(
            HealthKitClient.backgroundDeliveryOutcome(
                success: true,
                error: nil
            ),
            .succeeded
        )
        XCTAssertEqual(
            HealthKitClient.backgroundDeliveryOutcome(
                success: false,
                error: nil
            ),
            .failed(.unsuccessful)
        )

        struct RegistrationError: Error {}
        XCTAssertEqual(
            HealthKitClient.backgroundDeliveryOutcome(
                success: true,
                error: RegistrationError()
            ),
            .failed(
                .errorType(
                    String(reflecting: RegistrationError.self)
                )
            )
        )
        XCTAssertEqual(
            HealthKitClient.backgroundDeliveryOutcome(
                success: false,
                error: NSError(domain: HKErrorDomain, code: 7)
            ),
            .failed(.healthKit(7))
        )
    }

    func testBackgroundDeliverySummaryWarnsOnlyForEnableFailures() {
        let summary = BackgroundDeliveryRegistrationSummary(
            results: [
                BackgroundDeliveryRegistrationResult(
                    metric: .stepCount,
                    operation: .enable,
                    outcome: .failed(.unsuccessful)
                ),
                BackgroundDeliveryRegistrationResult(
                    metric: .sleep,
                    operation: .disable,
                    outcome: .failed(.healthKit(1))
                ),
            ]
        )

        XCTAssertEqual(summary.failedEnabledMetrics, [.stepCount])
    }

    func testBackgroundDeliveryAdvisoryListsMetricsAndManualFallback() throws {
        let advisory = try XCTUnwrap(
            BackgroundDeliveryAdvisory(
                failedMetrics: [.sleep, .stepCount]
            )
        )

        XCTAssertEqual(advisory.metrics, [.stepCount, .sleep])
        XCTAssertTrue(advisory.message.contains("Steps and Sleep"))
        let threeMetricAdvisory = try XCTUnwrap(
            BackgroundDeliveryAdvisory(
                failedMetrics: [.bodyMass, .stepCount, .sleep]
            )
        )
        XCTAssertTrue(
            threeMetricAdvisory.message.contains(
                "Body mass, Steps, and Sleep"
            )
        )
        XCTAssertNil(BackgroundDeliveryAdvisory(failedMetrics: []))
    }

    func testLatestBackgroundDeliveryResultReplacesAndClearsAdvisoryState() {
        var state = BackgroundDeliveryRegistrationState()

        state.apply(
            BackgroundDeliveryRegistrationSummary(
                results: [
                    BackgroundDeliveryRegistrationResult(
                        metric: .stepCount,
                        operation: .enable,
                        outcome: .failed(.unsuccessful)
                    )
                ]
            )
        )
        XCTAssertEqual(state.failedEnabledMetrics, [.stepCount])

        state.apply(
            BackgroundDeliveryRegistrationSummary(
                results: [
                    BackgroundDeliveryRegistrationResult(
                        metric: .stepCount,
                        operation: .enable,
                        outcome: .succeeded
                    )
                ]
            )
        )

        XCTAssertTrue(state.failedEnabledMetrics.isEmpty)
    }

    func testHealthReadTypesFollowEnabledMetricSelection() throws {
        let selected: Set<HealthMetric> = [.stepCount, .sleep]
        let readTypes = HealthMetric.readTypes(for: selected)

        XCTAssertEqual(readTypes.count, 2)
        XCTAssertTrue(
            readTypes.contains(
                try XCTUnwrap(HealthMetric.stepCount.sampleType)
            )
        )
        XCTAssertTrue(
            readTypes.contains(
                try XCTUnwrap(HealthMetric.sleep.sampleType)
            )
        )
        XCTAssertFalse(
            readTypes.contains(
                try XCTUnwrap(HealthMetric.bodyMass.sampleType)
            )
        )
        XCTAssertTrue(HealthMetric.readTypes(for: []).isEmpty)
    }

    func testQueryableMetricsUseRequestedSubsetAndMigrateLegacyState() async throws {
        let suiteName = "HealthMuleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(true, forKey: "health.authorization.requested")
        defaults.set(
            [HealthMetric.stepCount.rawValue],
            forKey: "health.authorization.requestedMetrics"
        )
        let boundaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: boundaryDirectory)
        }
        let client = HealthKitClient(
            store: HKHealthStore(),
            anchorDirectoryURL: boundaryDirectory.appendingPathComponent(
                "anchors",
                isDirectory: true
            ),
            dayBoundaryDirectoryURL: boundaryDirectory,
            defaultsSuiteName: suiteName
        )
        let enabled: Set<HealthMetric> = [.stepCount, .sleep]

        let requestedSubset = await client.queryableMetrics(from: enabled)
        XCTAssertEqual(requestedSubset, [.stepCount])

        defaults.removeObject(
            forKey: "health.authorization.requestedMetrics"
        )
        let migratedSubset = await client.queryableMetrics(from: enabled)
        XCTAssertEqual(migratedSubset, enabled)
    }

    func testPreauthorizationCountExcludesMetricsThatAreNotIncluded() {
        let statuses = [
            MetricStatus(metric: .stepCount, state: .notRequested),
            MetricStatus(metric: .sleep, state: .notIncluded),
            MetricStatus(metric: .bodyMass, state: .notRequested),
        ]

        XCTAssertEqual(statuses.includedMetricCount, 2)
    }

    func testHistoryChangeDuringReconciliationQueuesFollowUpPass() {
        var queue = SelectionReconciliationQueue()

        queue.beginPass()
        queue.enqueue(.historySelection)

        XCTAssertEqual(queue.followUpTrigger, .historySelection)
        queue.beginPass()
        XCTAssertNil(queue.followUpTrigger)
    }

    func testMetricAndHistoryChangesCoalesceIntoOneHistoryFollowUpPass() {
        var queue = SelectionReconciliationQueue()

        queue.enqueue(.metricSelection)
        queue.enqueue(.historySelection)

        XCTAssertEqual(queue.followUpTrigger, .historySelection)
    }

    func testObserverFlushRequestsCoalesceWhileDrainIsActive() {
        var queue = ObserverFlushQueue()

        XCTAssertTrue(queue.request())
        XCTAssertFalse(queue.request())
        XCTAssertTrue(queue.isDraining)
        XCTAssertTrue(queue.beginPass())
        XCTAssertFalse(queue.beginPass())
        queue.finish()

        XCTAssertFalse(queue.isDraining)
        XCTAssertTrue(queue.request())
    }

    func testObserverFlushRequestDuringPassCreatesOneFollowUp() {
        var queue = ObserverFlushQueue()

        XCTAssertTrue(queue.request())
        XCTAssertTrue(queue.beginPass())
        XCTAssertFalse(queue.request())
        XCTAssertFalse(queue.request())
        XCTAssertTrue(queue.beginPass())
        XCTAssertFalse(queue.beginPass())
        queue.finish()

        XCTAssertFalse(queue.isDraining)
    }

    func testDriveReadinessRequiresVerifiedFolder() {
        let account = GoogleAccount(
            id: "google-user",
            email: "person@example.com"
        )
        let authorized = GoogleConnectionState.authorized(account)
        let connected = GoogleConnectionState.connected(
            GoogleConnection(
                account: account,
                folderID: "folder-id",
                folderName: "Apple Health Sync"
            )
        )

        XCTAssertTrue(authorized.isAuthorized)
        XCTAssertFalse(authorized.isDriveReady)
        XCTAssertTrue(authorized.canDisconnect)
        XCTAssertTrue(connected.isAuthorized)
        XCTAssertTrue(connected.isDriveReady)
        XCTAssertFalse(GoogleConnectionState.restoring.canDisconnect)
    }

    func testSyncReadinessKeepsAuthorizationAndDriveSetupDistinct() {
        let account = GoogleAccount(
            id: "google-user",
            email: nil
        )
        let connected = GoogleConnectionState.connected(
            GoogleConnection(
                account: account,
                folderID: "folder-id",
                folderName: "Apple Health Sync"
            )
        )

        XCTAssertEqual(
            SyncReadiness.resolve(
                health: .checking,
                google: .connected(
                    GoogleConnection(
                        account: account,
                        folderID: "folder-id",
                        folderName: "Apple Health Sync"
                    )
                )
            ),
            .checkingConnections
        )
        XCTAssertEqual(
            SyncReadiness.resolve(
                health: .requestCompleted,
                google: .authorized(account)
            ),
            .googleDriveSetupRequired
        )
        XCTAssertEqual(
            SyncReadiness.resolve(
                health: .requestCompleted,
                google: .driveUnavailable(account)
            ),
            .googleDriveUnavailable
        )
        XCTAssertEqual(
            SyncReadiness.resolve(
                health: .requestCompleted,
                google: .connected(
                    GoogleConnection(
                        account: account,
                        folderID: "folder-id",
                        folderName: "Apple Health Sync"
                    )
                )
            ),
            .ready
        )
        let reviewReadiness = SyncReadiness.resolve(
            health: .reviewRequired,
            google: connected
        )
        XCTAssertEqual(reviewReadiness, .healthReviewRecommended)
        XCTAssertTrue(reviewReadiness.canSync)
    }

    func testSyncReadinessRequiresLocalProtectedStorage() {
        let account = GoogleAccount(
            id: "google-user",
            email: nil
        )
        let connected = GoogleConnectionState.connected(
            GoogleConnection(
                account: account,
                folderID: "folder-id",
                folderName: "Apple Health Sync"
            )
        )

        let readiness = SyncReadiness.resolve(
            health: .requestCompleted,
            google: connected,
            localStorageAvailable: false
        )

        XCTAssertEqual(readiness, .localStorageUnavailable)
        XCTAssertFalse(readiness.canSync)
    }

    func testHealthReviewDoesNotBlockPreviouslyReadableTypes() {
        XCTAssertTrue(HealthAuthorizationState.reviewRequired.allowsQueries)
        XCTAssertTrue(HealthAuthorizationState.requestCompleted.allowsQueries)
        XCTAssertTrue(
            HealthAuthorizationState.statusUnavailable(
                previouslyRequested: true
            ).allowsQueries
        )
        XCTAssertFalse(
            HealthAuthorizationState.statusUnavailable(
                previouslyRequested: false
            ).allowsQueries
        )
        XCTAssertFalse(HealthAuthorizationState.notRequested.allowsQueries)
        XCTAssertFalse(HealthAuthorizationState.unavailable.allowsQueries)
    }

    func testHealthStatusFailurePreservesPriorQueryability() {
        let account = GoogleAccount(id: "google-user", email: nil)
        let connected = GoogleConnectionState.connected(
            GoogleConnection(
                account: account,
                folderID: "folder-id",
                folderName: "Apple Health Sync"
            )
        )

        let previouslyRequested = SyncReadiness.resolve(
            health: .statusUnavailable(previouslyRequested: true),
            google: connected
        )
        let neverRequested = SyncReadiness.resolve(
            health: .statusUnavailable(previouslyRequested: false),
            google: connected
        )

        XCTAssertEqual(
            previouslyRequested,
            .healthStatusUnavailable(canSync: true)
        )
        XCTAssertTrue(previouslyRequested.canSync)
        XCTAssertEqual(
            neverRequested,
            .healthStatusUnavailable(canSync: false)
        )
        XCTAssertFalse(neverRequested.canSync)
    }

    @MainActor
    func testForegroundRefreshKeepsKnownHealthPresentationWhileChecking() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw XCTSkip("HealthKit is unavailable on this test device.")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "HealthMuleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set(true, forKey: "health.authorization.requested")
        defaults.set([String](), forKey: "health.authorization.requestedMetrics")
        let changedKeys = ["backfill.customStart", "backfill.selectedStart"]
        let previous = changedKeys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            for (key, value) in zip(changedKeys, previous) {
                if let value { UserDefaults.standard.set(value, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            try? FileManager.default.removeItem(at: directory)
        }

        let requested = expectation(description: "Passive Health status request started")
        let gate = PassiveHealthStatusGate(requested: requested)
        let health = HealthKitClient(
            store: PassiveHealthStatusStore(gate: gate),
            anchorDirectoryURL: directory.appendingPathComponent("anchors"),
            dayBoundaryDirectoryURL: directory.appendingPathComponent("boundaries"),
            defaultsSuiteName: suiteName
        )
        let configuration = GoogleOAuthConfiguration(clientID: "", redirectScheme: "")
        let drive = DriveAPIClient(
            tokenProvider: { _ in throw GoogleAuthError.configurationMissing },
            metadataStore: DriveMetadataStore(
                directoryURL: directory.appendingPathComponent("drive")
            ),
            uploadTransport: UnexpectedPassiveRefreshUploadTransport()
        )
        let diagnostics = DiagnosticsRecorder(
            exportDirectory: directory.appendingPathComponent("diagnostics")
        )
        let coordinator = try LiveSyncCoordinator(
            rootDirectory: directory.appendingPathComponent("staging"),
            healthKit: health,
            recordProvider: HealthKitDailyRecordProvider(healthKit: health),
            destination: DriveArtifactDestination(driveClient: drive),
            diagnostics: diagnostics,
            defaultsSuiteName: suiteName
        )
        let model = AppModel(
            googleConfiguration: configuration,
            googleAuth: GoogleAuthService(configuration: configuration),
            driveClient: drive,
            healthKit: health,
            diagnostics: diagnostics,
            syncActivityStore: SyncActivityStore(
                directoryURL: directory.appendingPathComponent("activity")
            ),
            stagingRoot: directory.appendingPathComponent("staging"),
            syncCoordinator: coordinator,
            syncInitializationError: nil,
            isUITesting: false
        )
        model.enabledMetrics = []
        await model.bootstrap()
        XCTAssertEqual(model.healthAuthorizationState, .requestCompleted)

        model.enabledMetrics = [.stepCount]
        let knownStatuses = HealthMetric.allCases.map {
            MetricStatus(
                metric: $0,
                state: $0 == .stepCount ? .noReadableData : .notIncluded
            )
        }
        model.metricStatuses = knownStatuses
        let refresh = Task { @MainActor in
            await model.applicationDidBecomeActive()
        }
        await fulfillment(of: [requested], timeout: 5)
        XCTAssertEqual(model.healthAuthorizationState, .requestCompleted)
        XCTAssertEqual(model.metricStatuses, knownStatuses)
        await gate.release()
        await refresh.value
    }

    func testNonSyncFailureDoesNotBecomeSyncFailure() {
        let connectionFailure = OperationState.failed(
            .googleConnection,
            "Unavailable"
        )
        let syncFailure = OperationState.failed(.sync, "Upload failed")

        XCTAssertFalse(connectionFailure.isFailure(.sync))
        XCTAssertTrue(syncFailure.isFailure(.sync))
    }

    @MainActor
    func testPendingSummaryDoesNotBecomeSuccessfulSyncState() {
        let summary = SyncSummary(
            lastSuccessfulSyncAt: nil,
            latestExportedDate: "2026-07-23",
            pendingUploadCount: 2,
            retryableUploadCount: 2,
            permanentFailureCount: 0
        )

        let state = AppModel.syncCompletionState(
            report: SyncReport(),
            summary: summary
        )

        XCTAssertTrue(state.isWarning(.sync))
        XCTAssertFalse(state.isFailure(.sync))
    }

    @MainActor
    func testPermanentFailureSummaryBecomesFailedSyncState() {
        let summary = SyncSummary(
            lastSuccessfulSyncAt: nil,
            latestExportedDate: "2026-07-23",
            pendingUploadCount: 1,
            retryableUploadCount: 0,
            permanentFailureCount: 1
        )

        let state = AppModel.syncCompletionState(
            report: SyncReport(),
            summary: summary
        )

        XCTAssertTrue(state.isFailure(.sync))
        XCTAssertFalse(state.isWarning(.sync))
    }

    @MainActor
    func testObserverCompletionReplacesStaleSyncBanner() {
        let state = AppModel.observerSyncCompletionState(
            replacing: .failed(.sync, "An older upload failed."),
            report: SyncReport(),
            summary: .empty
        )

        XCTAssertEqual(
            state,
            .succeeded(.sync, "Everything is up to date.")
        )
    }

    @MainActor
    func testObserverCompletionPreservesUnrelatedOperationBanner() {
        let state = AppModel.observerSyncCompletionState(
            replacing: .succeeded(
                .diagnostics,
                "Diagnostics are ready to share."
            ),
            report: SyncReport(),
            summary: .empty
        )

        XCTAssertNil(state)
    }

    @MainActor
    func testObserverCompletionDoesNotRepublishIdenticalSyncBanner() {
        let state = AppModel.observerSyncCompletionState(
            replacing: .succeeded(
                .sync,
                "Everything is up to date."
            ),
            report: SyncReport(),
            summary: .empty
        )

        XCTAssertNil(state)
    }

    @MainActor
    func testDriveDestinationChangeReportRequiresInvalidation() {
        var report = SyncReport()
        report.failures = [
            SyncFailureSummary(
                artifactID: .manifest,
                code: "drive_destination_changed",
                blocked: true
            )
        ]

        XCTAssertTrue(AppModel.driveDestinationChanged(in: report))
    }

    func testResetMetadataContractClearsOnlyLocalSyncProgress() throws {
        let suiteName = "HealthMuleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(Date(), forKey: "sync.lastSuccessful")
        defaults.set(["steps"], forKey: "sync.lastStagedMetrics")
        defaults.set(
            "2026-07-01",
            forKey: "sync.lastStagedBackfillStart"
        )
        defaults.set(
            2,
            forKey: "sync.lastStagedExportContractRevision"
        )
        defaults.set(
            "preserved-destination",
            forKey: "sync.destinationAccountNamespace.v1"
        )

        LiveSyncCoordinator.clearPersistedResetMetadata(
            defaults: defaults
        )

        XCTAssertNil(defaults.object(forKey: "sync.lastSuccessful"))
        XCTAssertNil(defaults.object(forKey: "sync.lastStagedMetrics"))
        XCTAssertNil(
            defaults.object(forKey: "sync.lastStagedBackfillStart")
        )
        XCTAssertNil(
            defaults.object(
                forKey: "sync.lastStagedExportContractRevision"
            )
        )
        XCTAssertEqual(
            defaults.string(
                forKey: "sync.destinationAccountNamespace.v1"
            ),
            "preserved-destination"
        )
    }

    func testAppBundleContainsIconAndPrivacyManifest() throws {
        let icons = try XCTUnwrap(
            Bundle.main.infoDictionary?["CFBundleIcons"]
                as? [String: Any]
        )
        let primaryIcon = try XCTUnwrap(
            icons["CFBundlePrimaryIcon"] as? [String: Any]
        )

        XCTAssertEqual(primaryIcon["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertNotNil(
            Bundle.main.url(forResource: "Assets", withExtension: "car")
        )
        let privacyURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "PrivacyInfo",
                withExtension: "xcprivacy"
            )
        )
        let privacyData = try Data(contentsOf: privacyURL)
        let privacyManifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: privacyData,
                format: nil
            ) as? [String: Any]
        )
        let collectedTypes = try XCTUnwrap(
            privacyManifest["NSPrivacyCollectedDataTypes"]
                as? [[String: Any]]
        )
        let declarations = Dictionary(
            uniqueKeysWithValues: collectedTypes.compactMap { declaration in
                (declaration["NSPrivacyCollectedDataType"] as? String).map {
                    ($0, declaration)
                }
            }
        )
        for type in [
            "NSPrivacyCollectedDataTypeHealth",
            "NSPrivacyCollectedDataTypeFitness",
        ] {
            let declaration = try XCTUnwrap(declarations[type])
            XCTAssertEqual(
                declaration["NSPrivacyCollectedDataTypeLinked"] as? Bool,
                true
            )
            XCTAssertEqual(
                declaration["NSPrivacyCollectedDataTypeTracking"] as? Bool,
                false
            )
            XCTAssertEqual(
                declaration["NSPrivacyCollectedDataTypePurposes"] as? [String],
                ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
            )
        }
    }

    func testPlaceholderGoogleConfigurationIsNotReady() {
        let configuration = GoogleOAuthConfiguration(
            clientID: "",
            redirectScheme: "dev.uinaf.healthmule.oauth.unconfigured"
        )

        XCTAssertFalse(configuration.isConfigured)
    }

    func testGoogleConfigurationRequiresExactReversedClientIDScheme() {
        let clientPrefix = "123456789-example-client"
        let clientID = clientPrefix + ".apps.googleusercontent.com"
        let configuration = GoogleOAuthConfiguration(
            clientID: clientID,
            redirectScheme: "com.googleusercontent.apps." + clientPrefix
        )
        let mismatchedConfiguration = GoogleOAuthConfiguration(
            clientID: clientID,
            redirectScheme: "com.googleusercontent.apps.987654321-other-client"
        )

        XCTAssertTrue(configuration.isConfigured)
        XCTAssertFalse(mismatchedConfiguration.isConfigured)
    }

    func testRevokedRefreshGrantRequiresReauthorization() {
        let error = NSError(
            domain: "org.openid.appauth.oauth_token",
            code: -10
        )

        XCTAssertEqual(
            GoogleAuthService.refreshError(for: error),
            .reauthorizationRequired
        )
    }

    func testRefreshNetworkFailureRemainsRetryable() {
        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: URLError.notConnectedToInternet.rawValue
        )
        let error = NSError(
            domain: "org.openid.appauth.general",
            code: -5,
            userInfo: [NSUnderlyingErrorKey: networkError]
        )

        XCTAssertEqual(
            GoogleAuthService.refreshError(for: error),
            .refreshTemporarilyUnavailable
        )
    }

    func testBackfillSelectionKeepsItsCalendarDayAcrossTimeZones() throws {
        let sourceTimeZone = try XCTUnwrap(
            TimeZone(identifier: "Europe/Istanbul")
        )
        let sourceCalendar = LocalDayCalendar.make(
            timeZone: sourceTimeZone
        )
        let selectedDate = try XCTUnwrap(
            sourceCalendar.date(
                from: DateComponents(year: 2026, month: 7, day: 23)
            )
        )
        let storedValue = BackfillDateCodec.string(
            from: selectedDate,
            timeZone: sourceTimeZone
        )

        let destinationTimeZone = try XCTUnwrap(
            TimeZone(identifier: "America/New_York")
        )
        XCTAssertEqual(
            BackfillDateCodec.string(
                from: selectedDate,
                timeZone: destinationTimeZone
            ),
            "2026-07-22",
            "An absolute Date is not a stable source of truth after travel."
        )
        let restoredDate = try XCTUnwrap(
            BackfillDateCodec.date(
                from: storedValue,
                timeZone: destinationTimeZone
            )
        )

        XCTAssertEqual(
            BackfillDateCodec.string(
                from: restoredDate,
                timeZone: destinationTimeZone
            ),
            "2026-07-23"
        )
    }
}

private actor PassiveHealthStatusGate {
    typealias Completion = @Sendable (HKAuthorizationRequestStatus, Error?) -> Void
    private let requested: XCTestExpectation
    private var completion: Completion?
    private var released = false

    init(requested: XCTestExpectation) {
        self.requested = requested
    }

    func hold(_ completion: @escaping Completion) {
        self.completion = completion
        requested.fulfill()
        if released { finish() }
    }

    func release() {
        released = true
        finish()
    }

    private func finish() {
        let callback = completion
        completion = nil
        callback?(.unknown, NSError(domain: "HealthMuleTests", code: 1))
    }
}

private final class PassiveHealthStatusStore: HKHealthStore, @unchecked Sendable {
    private let gate: PassiveHealthStatusGate

    init(gate: PassiveHealthStatusGate) {
        self.gate = gate
        super.init()
    }

    override func getRequestStatusForAuthorization(
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>,
        completion: @escaping @Sendable (HKAuthorizationRequestStatus, Error?) -> Void
    ) {
        Task { await gate.hold(completion) }
    }

    override func execute(_ query: HKQuery) {}
    override func stop(_ query: HKQuery) {}

    override func enableBackgroundDelivery(
        for type: HKObjectType,
        frequency: HKUpdateFrequency,
        withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        completion(true, nil)
    }

    override func disableBackgroundDelivery(
        for type: HKObjectType,
        withCompletion completion: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        completion(true, nil)
    }
}

private struct UnexpectedPassiveRefreshUploadTransport: DriveUploadTransport {
    func transition(toDestinationScopeID destinationScopeID: String?) async throws {}

    func upload(
        request: URLRequest,
        body: Data,
        operationID: String,
        destinationScopeID: String
    ) async throws -> DriveUploadResponse {
        XCTFail("Passive Health refresh must not upload while Google is unconfigured.")
        throw GoogleAuthError.configurationMissing
    }
}
