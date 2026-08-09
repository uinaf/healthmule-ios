import XCTest

final class HealthMuleUITests: XCTestCase {
    @MainActor
    func testAppShellUsesFocusedNavigation() throws {
        let app = launch()

        XCTAssertTrue(app.navigationBars["HealthMule"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("home-screen", in: app).exists)
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
        XCTAssertFalse(app.tabBars.buttons["Setup"].exists)
        XCTAssertFalse(app.tabBars.buttons["Sync"].exists)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(element("settings-screen", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testSetupCallToActionOpensSetupFlow() throws {
        let app = launch()
        let setupAction = element("open-setup-action", in: app)

        XCTAssertTrue(setupAction.waitForExistence(timeout: 10))
        setupAction.tap()

        XCTAssertTrue(element("setup-screen", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("google-state", in: app).exists)
    }

    @MainActor
    func testSyncActionsRequireReadyConnections() throws {
        let app = launch(additionalArguments: ["--ui-show-sync"])

        XCTAssertTrue(element("sync-screen", in: app).waitForExistence(timeout: 10))

        let syncNow = element("sync-now-action", in: app)
        let reviewSetup = element("sync-setup-action", in: app)
        let retry = element("retry-uploads-action", in: app)
        let rebuild = element("rebuild-action", in: app)
        XCTAssertFalse(syncNow.exists)
        XCTAssertTrue(reviewSetup.exists)
        XCTAssertTrue(reviewSetup.isEnabled)
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(retry.isEnabled)
        XCTAssertTrue(rebuild.exists)
        XCTAssertFalse(rebuild.isEnabled)
    }

    @MainActor
    func testReadyEmptyQueueSyncActionsHaveCorrectAvailability() throws {
        let app = launch(
            additionalArguments: ["--ui-show-sync", "--ui-ready"]
        )

        XCTAssertTrue(element("sync-screen", in: app).waitForExistence(timeout: 10))

        let syncNow = element("sync-now-action", in: app)
        let retry = element("retry-uploads-action", in: app)
        let rebuild = element("rebuild-action", in: app)
        XCTAssertTrue(syncNow.exists)
        XCTAssertTrue(syncNow.isEnabled)
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(retry.isEnabled)
        XCTAssertTrue(rebuild.exists)
        XCTAssertTrue(rebuild.isEnabled)
    }

    @MainActor
    func testDeterminateSyncProgressIsAccessibleOnBothSurfaces() throws {
        let arguments = [
            "--ui-ready",
            "--ui-operation-working",
            "--ui-sync-progress",
        ]
        let homeApp = launch(additionalArguments: arguments)
        let homeProgress = element("sync-day-progress", in: homeApp)

        XCTAssertTrue(homeProgress.waitForExistence(timeout: 10))
        XCTAssertEqual(
            homeProgress.value as? String,
            "Processing 12 of 30 days"
        )
        homeApp.terminate()

        let syncApp = launch(
            additionalArguments: arguments + ["--ui-show-sync"]
        )
        let syncProgress = element("sync-day-progress", in: syncApp)

        XCTAssertTrue(syncProgress.waitForExistence(timeout: 10))
        XCTAssertEqual(
            syncProgress.value as? String,
            "Processing 12 of 30 days"
        )
    }

    @MainActor
    func testConnectionCardsDistinguishRequestAuthAndDriveReadiness() throws {
        let app = launch(
            additionalArguments: [
                "--ui-health-request-complete",
                "--ui-health-readable",
                "--ui-google-authorized",
            ]
        )

        XCTAssertTrue(
            element("health-connection-card", in: app)
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Request complete"].exists)
        XCTAssertTrue(app.staticTexts["3 types have visible data"].exists)
        XCTAssertTrue(app.staticTexts["Finishing setup"].exists)
        XCTAssertFalse(app.staticTexts["Connected"].exists)
    }

    @MainActor
    func testDriveUnavailableIsNotPresentedAsConnected() throws {
        let app = launch(
            additionalArguments: [
                "--ui-health-request-complete",
                "--ui-google-drive-unavailable",
            ]
        )

        XCTAssertTrue(
            element("google-connection-card", in: app)
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Drive unavailable"].exists)
        XCTAssertFalse(app.staticTexts["Connected"].exists)
    }

    @MainActor
    func testWorkingStateUsesHeroAndDisablesSyncAction() throws {
        let app = launch(
            additionalArguments: ["--ui-ready", "--ui-operation-working"]
        )

        XCTAssertTrue(
            element("status-hero-title", in: app)
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Syncing your latest changes"].exists)
        XCTAssertFalse(element("operation-status", in: app).exists)
        XCTAssertFalse(element("home-sync-action", in: app).isEnabled)
    }

    @MainActor
    func testInitialLoadingShowsNoPersistedSyncFacts() throws {
        let app = launch(additionalArguments: ["--ui-initial-loading"])

        XCTAssertTrue(
            element("sync-summary-loading", in: app)
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Loading your sync status"].exists)
        XCTAssertFalse(app.staticTexts["Never"].exists)
        XCTAssertFalse(app.staticTexts["None"].exists)
        XCTAssertFalse(app.staticTexts["0"].exists)
    }

    @MainActor
    func testAutomaticFailureDoesNotAppearOnHomeOrSync() throws {
        let arguments = ["--ui-ready", "--ui-operation-failed-automatic"]
        let homeApp = launch(additionalArguments: arguments)

        XCTAssertTrue(
            homeApp.staticTexts["Ready for the first sync"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(homeApp.staticTexts["Sync needs another look"].exists)
        XCTAssertFalse(element("operation-status", in: homeApp).exists)
        homeApp.terminate()

        let syncApp = launch(
            additionalArguments: arguments + ["--ui-show-sync"]
        )

        XCTAssertTrue(
            syncApp.staticTexts["Ready for the first sync"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(syncApp.staticTexts["Sync needs another look"].exists)
        XCTAssertFalse(element("operation-status", in: syncApp).exists)
    }

    @MainActor
    func testUserFailureRemainsVisibleOnHomeAndSync() throws {
        let arguments = ["--ui-ready", "--ui-operation-failed-user"]
        let homeApp = launch(additionalArguments: arguments)

        XCTAssertTrue(
            homeApp.staticTexts["Sync needs another look"]
                .waitForExistence(timeout: 10)
        )
        homeApp.terminate()

        let syncApp = launch(
            additionalArguments: arguments + ["--ui-show-sync"]
        )

        XCTAssertTrue(
            syncApp.staticTexts["Sync needs another look"]
                .waitForExistence(timeout: 10)
        )
    }

    @MainActor
    func testHeroAccessibilityChildOrderIsStableAcrossTones() throws {
        let fixtures: [([String], String)] = [
            (
                ["--ui-health-review", "--ui-google-connected"],
                "Apple Health access needs review"
            ),
            (
                ["--ui-ready", "--ui-permanent-failure"],
                "An upload was rejected"
            ),
            (
                ["--ui-ready", "--ui-synced"],
                "Everything is in sync"
            ),
        ]

        for (arguments, title) in fixtures {
            let app = launch(additionalArguments: arguments)
            XCTAssertTrue(
                app.staticTexts[title].waitForExistence(timeout: 10)
            )
            assertHeroAccessibilityChildOrder(in: app)
            app.terminate()
        }
    }

    @MainActor
    func testHistorySelectionIsDisabledWhileWorkIsVisible() throws {
        let app = launch(
            additionalArguments: ["--ui-ready", "--ui-operation-working"]
        )
        let healthCard = element("health-connection-card", in: app)

        XCTAssertTrue(healthCard.waitForExistence(timeout: 10))
        healthCard.tap()

        XCTAssertTrue(element("setup-screen", in: app).waitForExistence(timeout: 5))
        let picker = element("backfill-range-picker", in: app)
        XCTAssertTrue(picker.exists)
        XCTAssertFalse(picker.isEnabled)
    }

    @MainActor
    func testCheckingHealthDoesNotFlashFalseZero() throws {
        let app = launch(
            additionalArguments: [
                "--ui-health-checking",
                "--ui-google-restoring",
            ]
        )

        XCTAssertTrue(
            app.staticTexts["Checking Health data"].waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.staticTexts["0 types have visible data"].exists)
        XCTAssertFalse(element("open-setup-action", in: app).exists)
    }

    @MainActor
    func testRestoringGoogleDoesNotOfferDisconnect() throws {
        let app = launch(
            additionalArguments: [
                "--ui-health-request-complete",
                "--ui-google-restoring",
            ]
        )
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(element("settings-screen", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Disconnect Google"].exists)
    }

    @MainActor
    func testHealthReviewRemainsSyncableWithoutLookingFullyReady() throws {
        let app = launch(
            additionalArguments: [
                "--ui-health-review",
                "--ui-google-connected",
                "--ui-show-sync",
            ]
        )

        XCTAssertTrue(element("sync-screen", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Review suggested"].exists)
        XCTAssertTrue(element("sync-now-action", in: app).isEnabled)
    }

    @MainActor
    func testFailedHealthStatusCheckPreservesPriorSyncability() throws {
        let app = launch(
            additionalArguments: [
                "--ui-health-status-unavailable",
                "--ui-health-previously-requested",
                "--ui-google-connected",
                "--ui-show-sync",
            ]
        )

        XCTAssertTrue(element("sync-screen", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Check failed"].exists)
        XCTAssertTrue(element("sync-now-action", in: app).isEnabled)
        XCTAssertFalse(app.staticTexts["Request complete"].exists)
    }

    @MainActor
    func testFailedInitialHealthStatusCheckBlocksSync() throws {
        let app = launch(
            additionalArguments: [
                "--ui-health-status-unavailable",
                "--ui-google-connected",
                "--ui-show-sync",
            ]
        )

        XCTAssertTrue(element("sync-screen", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Apple Health status is unavailable"].exists)
        XCTAssertFalse(element("sync-now-action", in: app).exists)
        XCTAssertTrue(element("sync-setup-action", in: app).exists)
    }

    @MainActor
    func testPermanentFailureIsNotAdvertisedAsRetryable() throws {
        let app = launch(
            additionalArguments: [
                "--ui-ready",
                "--ui-show-sync",
                "--ui-permanent-failure",
            ]
        )

        XCTAssertTrue(element("sync-screen", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Upload blocked"].exists)
        XCTAssertFalse(element("retry-uploads-action", in: app).isEnabled)
    }

    @MainActor
    private func launch(
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + additionalArguments
        app.launch()
        return app
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func assertHeroAccessibilityChildOrder(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let identifiers = [
            "status-hero-badge",
            "status-hero-title",
            "status-hero-message",
        ]
        let actual = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .map(\.identifier)
            .filter(identifiers.contains)

        XCTAssertEqual(actual, identifiers, file: file, line: line)
    }
}
