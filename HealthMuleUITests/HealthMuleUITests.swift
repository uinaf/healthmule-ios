import XCTest

final class HealthMuleUITests: XCTestCase {
    @MainActor
    func testAppIsOneScreenWithoutTabs() throws {
        let app = launch(additionalArguments: ["--ui-ready"])

        XCTAssertTrue(app.navigationBars["HealthMule"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("home-screen", in: app).exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        app.buttons["settings-link"].firstMatch.tap()
        let advanced = element("advanced-link", in: app)
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        advanced.tap()
        XCTAssertTrue(element("advanced-screen", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testSetupRowsShowUntilConnectionsAreReady() throws {
        let app = launch()

        XCTAssertTrue(element("health-connection-row", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("google-connection-row", in: app).exists)
        XCTAssertTrue(element("health-authorization-action", in: app).isEnabled)
        XCTAssertFalse(element("sync-now-action", in: app).exists)
        app.terminate()

        let ready = launch(additionalArguments: ["--ui-ready"])
        XCTAssertTrue(element("sync-now-action", in: ready).waitForExistence(timeout: 10))
        XCTAssertFalse(element("health-connection-row", in: ready).exists)
        XCTAssertFalse(element("google-connection-row", in: ready).exists)
    }

    @MainActor
    func testConnectionRowsDistinguishRequestAndDriveReadiness() throws {
        let app = launch(additionalArguments: [
            "--ui-health-request-complete",
            "--ui-google-authorized",
        ])

        XCTAssertTrue(element("health-connection-row", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(value(of: "health-connection-row", in: app).contains("Requested"))
        XCTAssertTrue(value(of: "google-connection-row", in: app).contains("Finishing setup"))
        XCTAssertTrue(app.staticTexts["Preparing your Drive folder"].exists)
    }

    @MainActor
    func testAdvancedActionsRequireReadyConnections() throws {
        let app = launch(additionalArguments: ["--ui-show-advanced"])
        XCTAssertTrue(element("advanced-screen", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("retry-uploads-action", in: app).isEnabled)
        XCTAssertFalse(element("rebuild-action", in: app).isEnabled)
        app.terminate()

        let ready = launch(additionalArguments: ["--ui-ready", "--ui-show-advanced"])
        XCTAssertTrue(element("advanced-screen", in: ready).waitForExistence(timeout: 10))
        XCTAssertFalse(element("retry-uploads-action", in: ready).isEnabled)
        XCTAssertTrue(element("rebuild-action", in: ready).isEnabled)
    }

    @MainActor
    func testSyncShowsDayProgressAndDisablesSyncAction() throws {
        let app = launch(additionalArguments: [
            "--ui-ready",
            "--ui-operation-working",
            "--ui-sync-progress",
        ])
        let progress = element("sync-day-progress", in: app)

        XCTAssertTrue(progress.waitForExistence(timeout: 10))
        XCTAssertEqual(
            progress.value as? String,
            "Processing 12 of 30 days · Jul 12, 2026"
        )
        XCTAssertTrue(app.staticTexts["Syncing"].exists)
        XCTAssertEqual(
            app.staticTexts["sync-detail"].label,
            "Reading Jul 12 from Apple Health"
        )
        XCTAssertFalse(element("sync-now-action", in: app).exists)
    }

    @MainActor
    func testSyncWithoutProgressSaysItIsStarting() throws {
        let app = launch(additionalArguments: [
            "--ui-ready",
            "--ui-operation-working",
        ])

        XCTAssertTrue(app.staticTexts["Syncing"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["sync-detail"].label, "Starting")
    }

    @MainActor
    func testInitialLoadingShowsNoPersistedSyncFacts() throws {
        let app = launch(additionalArguments: ["--ui-initial-loading"])

        XCTAssertTrue(app.staticTexts["Loading"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("last-sync-fact", in: app).exists)
    }

    @MainActor
    func testHomeHidesSyncFactsBeforeFirstSync() throws {
        let app = launch(additionalArguments: ["--ui-ready"])

        XCTAssertTrue(element("sync-now-action", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("last-sync-fact", in: app).exists)
    }

    @MainActor
    func testAutomaticFailureStaysHiddenAndUserFailureShows() throws {
        let automatic = launch(additionalArguments: [
            "--ui-ready",
            "--ui-operation-failed-automatic",
        ])
        XCTAssertTrue(
            automatic.staticTexts["Ready to sync"].waitForExistence(timeout: 10)
        )
        XCTAssertFalse(automatic.staticTexts["Sync failed"].exists)
        XCTAssertEqual(element("sync-now-action", in: automatic).label, "Sync Now")
        automatic.terminate()

        let user = launch(additionalArguments: [
            "--ui-ready",
            "--ui-operation-failed-user",
        ])
        XCTAssertTrue(
            user.staticTexts["Sync failed"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(user.staticTexts["Manual sync failed."].exists)
        XCTAssertEqual(element("sync-now-action", in: user).label, "Try Again")
    }

    @MainActor
    func testDriveRetryShowsProgressAndFailure() throws {
        for (flag, message, isWorking) in [
            ("--ui-google-operation-working", "Checking Drive folder…", true),
            ("--ui-google-operation-failed", "Drive setup failed. Try again.", false),
        ] {
            let app = launch(additionalArguments: [
                "--ui-health-request-complete",
                "--ui-google-drive-unavailable",
                flag,
            ])
            let feedback = element("operation-status", in: app)
            XCTAssertTrue(feedback.waitForExistence(timeout: 10))
            XCTAssertTrue(feedback.label.contains(message))
            let retry = element("google-retry-action", in: app)
            scrollTo(retry, in: app)
            XCTAssertEqual(retry.isEnabled, !isWorking)
            capture(isWorking ? "drive-retry-working" : "drive-retry-failed", from: app)
            app.terminate()
        }
    }

    @MainActor
    func testHistorySelectionStaysEditableAndNeedsApplyDuringSync() throws {
        let app = launch(additionalArguments: ["--ui-ready", "--ui-operation-working", "--ui-show-settings"])
        let picker = element("backfill-range-picker", in: app)

        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        scrollTo(picker, in: app)
        XCTAssertTrue(picker.isEnabled)
        XCTAssertFalse(element("backfill-apply-action", in: app).exists)

        picker.tap()
        app.buttons["Last 90 days"].tap()

        let apply = element("backfill-apply-action", in: app)
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        XCTAssertTrue(apply.isEnabled)
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label BEGINSWITH 'The current sync stops'")
            ).firstMatch.exists
        )
        element("backfill-discard-action", in: app).tap()
        XCTAssertFalse(apply.exists)
    }

    @MainActor
    func testMetricChangesNeedApply() throws {
        let app = launch(additionalArguments: ["--ui-ready", "--ui-show-metrics"])
        XCTAssertTrue(element("metrics-screen", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("metrics-apply-action", in: app).exists)

        let sleep = app.switches["metric-toggle-sleep"]
        scrollTo(sleep, in: app)
        sleep.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        let apply = element("metrics-apply-action", in: app)
        scrollTo(apply, in: app)
        XCTAssertTrue(apply.isEnabled)
        let discard = element("metrics-discard-action", in: app)
        scrollTo(discard, in: app)
        discard.tap()
        XCTAssertFalse(apply.exists)
    }

    @MainActor
    func testUnavailableGoogleOffersDisconnectWithoutDriveDeletion() throws {
        for state in ["--ui-google-unavailable", "--ui-google-reconnect"] {
            let app = launch(additionalArguments: [state, "--ui-show-settings"])
            XCTAssertTrue(element("settings-screen", in: app).waitForExistence(timeout: 10))
            scrollTo(app.buttons["Disconnect Google"], in: app)
            app.terminate()

            let advanced = launch(additionalArguments: [state, "--ui-show-advanced"])
            XCTAssertTrue(element("advanced-screen", in: advanced).waitForExistence(timeout: 10))
            scrollTo(advanced.buttons["Reset Local Sync State"], in: advanced)
            XCTAssertFalse(advanced.buttons["Move Drive Exports to Trash"].exists)
            advanced.terminate()
        }
    }

    @MainActor
    func testDestructiveActionsUseCancellableAlerts() throws {
        let home = launch(additionalArguments: ["--ui-ready", "--ui-show-settings"])
        confirmAlertCancels(
            action: "Disconnect Google",
            title: "Disconnect Google?",
            in: home
        )
        home.terminate()

        let advanced = launch(additionalArguments: ["--ui-ready", "--ui-show-advanced"])
        XCTAssertTrue(element("advanced-screen", in: advanced).waitForExistence(timeout: 10))
        for (action, title) in [
            ("Move Drive Exports to Trash", "Move Drive exports to Trash?"),
            ("Reset Local Sync State", "Reset local sync state?"),
        ] {
            confirmAlertCancels(action: action, title: title, in: advanced)
        }
    }

    @MainActor
    func testFailedHealthCheckKeepsGoogleRecoveryReachable() throws {
        for (google, recovery) in [
            ("--ui-google-reconnect", "Reconnect Google Drive"),
            ("--ui-google-drive-unavailable", "google-retry-action"),
        ] {
            let app = launch(additionalArguments: ["--ui-health-status-failed", google])
            XCTAssertTrue(element("health-check-again-action", in: app).waitForExistence(timeout: 10))
            XCTAssertTrue(element(recovery, in: app).exists || app.buttons[recovery].exists)
            app.terminate()
        }
    }

    @MainActor
    func testHealthReviewRemainsSyncable() throws {
        let app = launch(additionalArguments: [
            "--ui-health-review",
            "--ui-google-connected",
        ])

        XCTAssertTrue(
            app.staticTexts["Review Apple Health access"].waitForExistence(timeout: 10)
        )
        XCTAssertTrue(element("sync-now-action", in: app).isEnabled)
        XCTAssertTrue(element("health-authorization-action", in: app).exists)
    }

    @MainActor
    func testPermanentFailureIsNotAdvertisedAsRetryable() throws {
        let app = launch(additionalArguments: ["--ui-ready", "--ui-permanent-failure"])

        XCTAssertTrue(app.staticTexts["Upload blocked"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("sync-now-action", in: app).exists)
        XCTAssertTrue(element("diagnostics-action", in: app).isEnabled)
        app.terminate()

        let advanced = launch(additionalArguments: [
            "--ui-ready",
            "--ui-permanent-failure",
            "--ui-show-advanced",
        ])
        XCTAssertTrue(element("advanced-screen", in: advanced).waitForExistence(timeout: 10))
        XCTAssertFalse(element("retry-uploads-action", in: advanced).isEnabled)
    }

    @MainActor
    func testAutomaticActivityReceipts() {
        let app = launch(additionalArguments: [
            "--ui-ready",
            "--ui-show-advanced",
            "--ui-activity-success",
        ])
        let latest = element("automatic-activity-latest", in: app)
        XCTAssertTrue(latest.waitForExistence(timeout: 10))
        XCTAssertTrue(value(of: "automatic-activity-latest", in: app).contains("Succeeded"))
        XCTAssertTrue(value(of: "automatic-activity-background", in: app).contains("Succeeded"))
        XCTAssertTrue(value(of: "automatic-activity-schedule", in: app).contains("Submitted"))
        app.terminate()

        let empty = launch(additionalArguments: ["--ui-ready", "--ui-show-advanced"])
        XCTAssertTrue(element("automatic-activity-latest", in: empty).waitForExistence(timeout: 10))
        XCTAssertTrue(value(of: "automatic-activity-latest", in: empty).contains("None"))
        XCTAssertTrue(value(of: "automatic-activity-schedule", in: empty).contains("None"))
    }

    @MainActor
    func testAgentHarnessCapturesCriticalStates() throws {
        let states: [(String, [String])] = [
            ("01-startup-loading", ["--ui-initial-loading"]),
            ("02-setup", []),
            ("03-sync-in-progress", ["--ui-ready", "--ui-operation-working", "--ui-sync-progress"]),
            ("04-user-visible-failure", ["--ui-ready", "--ui-operation-failed-user"]),
            ("05-blocked-upload", ["--ui-ready", "--ui-permanent-failure"]),
            ("06-metrics", ["--ui-ready", "--ui-show-metrics", "--ui-health-readable"]),
            ("07-advanced", ["--ui-ready", "--ui-show-advanced", "--ui-activity-success"]),
            ("08-home-dark", ["--ui-ready", "--ui-synced", "--ui-dark-mode"]),
            ("12-setup-dark", ["--ui-dark-mode"]),
            ("13-syncing-dark", ["--ui-ready", "--ui-operation-working", "--ui-sync-progress", "--ui-dark-mode"]),
            ("14-settings-dark", ["--ui-ready", "--ui-show-settings", "--ui-dark-mode"]),
            ("10-home-synced", ["--ui-ready", "--ui-synced"]),
            ("11-settings", ["--ui-ready", "--ui-show-settings"]),
            ("09-home-accessibility-text", ["--ui-ready", "--ui-accessibility-text"]),
        ]
        for (name, arguments) in states {
            let app = launch(additionalArguments: arguments)
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
            capture(name, from: app)
            app.terminate()
        }
    }

    @MainActor
    private func confirmAlertCancels(
        action: String,
        title: String,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
        let button = app.buttons[action]
        scrollTo(button, in: app)
        button.tap()
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        capture("alert-\(action)", from: app)
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.exists)
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
    private func capture(
        _ name: String,
        from app: XCUIApplication
    ) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        // Form rows load lazily, so off-screen rows do not exist yet.
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func element(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func value(
        of identifier: String,
        in app: XCUIApplication
    ) -> String {
        let element = element(identifier, in: app)
        return [element.label, element.value as? String ?? ""]
            .joined(separator: " ")
    }

}
