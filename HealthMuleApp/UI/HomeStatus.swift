import SwiftUI

/// The one-line answer to "is my export current?", shared by the home screen.
struct HomeStatus: Equatable {
    enum Action: Equatable {
        case sync(String)
        case retry
        case diagnostics
    }

    enum Tone: Equatable {
        case done
        case working
        case idle
        case waiting
        case setup
        case problem
    }

    let title: String
    var message: String?
    var tone: Tone
    var action: Action?

    var isProblem: Bool { tone == .problem }
    var isWorking: Bool { tone == .working }

    var symbol: String {
        switch tone {
        case .done: "checkmark.circle.fill"
        case .working: "arrow.triangle.2.circlepath"
        case .idle: "arrow.triangle.2.circlepath.circle.fill"
        case .waiting: "clock.fill"
        case .setup: "link.circle.fill"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch tone {
        case .done: .green
        case .working, .idle, .setup: .secondary
        case .waiting: .orange
        case .problem: .red
        }
    }

    @MainActor
    init(model: AppModel) {
        self = Self.resolve(model)
    }

    private init(
        _ title: String,
        _ message: String? = nil,
        tone: Tone,
        action: Action? = nil
    ) {
        self.title = title
        self.message = message
        self.tone = tone
        self.action = action
    }

    @MainActor
    private static func resolve(_ model: AppModel) -> HomeStatus {
        if model.initialLoadPhase == .loading {
            return HomeStatus("Loading", tone: .working)
        }
        if let blocked = setupStatus(model.syncReadiness) {
            return blocked
        }
        let summary = model.syncSummary
        if model.operationState.isWorking(.sync) {
            return HomeStatus("Syncing", tone: .working)
        }
        if summary.permanentFailureCount > 0 {
            return HomeStatus(
                "Upload blocked",
                "Drive rejected an upload. Share diagnostics before resetting.",
                tone: .problem,
                action: .diagnostics
            )
        }
        if case .failed(.sync, let message) = model.presentedOperationState {
            return HomeStatus(
                "Sync failed",
                message,
                tone: .problem,
                action: summary.retryableUploadCount > 0
                    ? .retry
                    : .sync("Try Again")
            )
        }
        if summary.pendingUploadCount > 0 {
            let count = summary.pendingUploadCount
            return HomeStatus(
                "\(count) upload\(count == 1 ? "" : "s") waiting",
                tone: .waiting,
                action: summary.retryableUploadCount > 0
                    ? .retry
                    : .sync("Sync Now")
            )
        }
        if model.syncReadiness == .healthReviewRecommended {
            return HomeStatus(
                "Review Apple Health access",
                tone: .waiting,
                action: .sync("Sync Now")
            )
        }
        if case .healthStatusUnavailable(canSync: true) = model.syncReadiness {
            return HomeStatus(
                "Couldn't check Apple Health",
                tone: .waiting,
                action: .sync("Sync Now")
            )
        }
        if summary.lastSuccessfulSyncAt == nil {
            return HomeStatus("Ready to sync", tone: .idle, action: .sync("Sync Now"))
        }
        return HomeStatus("Up to date", tone: .done, action: .sync("Sync Now"))
    }

    private static func setupStatus(_ readiness: SyncReadiness) -> HomeStatus? {
        switch readiness {
        case .localStorageUnavailable:
            HomeStatus(
                "Local storage unavailable",
                "Syncing is paused.",
                tone: .problem,
                action: .diagnostics
            )
        case .checkingConnections:
            HomeStatus("Checking connections", tone: .working)
        case .healthUnavailable:
            HomeStatus("Apple Health unavailable", tone: .problem)
        case .healthStatusUnavailable(canSync: false):
            HomeStatus("Couldn't check Apple Health", tone: .setup)
        case .healthRequestRequired:
            HomeStatus("Connect Apple Health", tone: .setup)
        case .googleNotConfigured:
            HomeStatus(
                "Google is not configured",
                "Add the OAuth client to Config/Secrets.xcconfig and rebuild.",
                tone: .problem
            )
        case .googleDisconnected:
            HomeStatus("Connect Google Drive", tone: .setup)
        case .googleTemporarilyUnavailable:
            HomeStatus("Google unavailable", tone: .waiting)
        case .googleReauthorizationRequired:
            HomeStatus("Reconnect Google Drive", tone: .problem)
        case .googleDriveSetupRequired:
            HomeStatus("Preparing your Drive folder", tone: .working)
        case .googleDriveUnavailable:
            HomeStatus("Drive folder unavailable", tone: .problem)
        case .healthStatusUnavailable(canSync: true),
             .healthReviewRecommended,
             .ready:
            nil
        }
    }
}
