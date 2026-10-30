import Foundation

/// The one-line answer to "is my export current?", shared by the home screen.
struct HomeStatus: Equatable {
    enum Action: Equatable {
        case sync(String)
        case retry
        case diagnostics
    }

    let title: String
    let message: String
    var isProblem = false
    var action: Action?

    @MainActor
    init(model: AppModel) {
        self = Self.resolve(model)
    }

    private init(
        title: String,
        message: String,
        isProblem: Bool = false,
        action: Action? = nil
    ) {
        self.title = title
        self.message = message
        self.isProblem = isProblem
        self.action = action
    }

    @MainActor
    private static func resolve(_ model: AppModel) -> HomeStatus {
        if model.initialLoadPhase == .loading {
            return HomeStatus(
                title: "Loading",
                message: "Restoring connections and sync history."
            )
        }
        if let blocked = setupStatus(model.syncReadiness) {
            return blocked
        }
        let summary = model.syncSummary
        if model.operationState.isWorking(.sync) {
            return HomeStatus(
                title: "Syncing",
                message: "Days are saved on this iPhone, then uploaded. You can keep using HealthMule."
            )
        }
        if summary.permanentFailureCount > 0 {
            return HomeStatus(
                title: "Upload blocked",
                message: "Drive rejected an upload. The local copy is safe; share diagnostics before resetting.",
                isProblem: true,
                action: .diagnostics
            )
        }
        if case .failed(.sync, let message) = model.presentedOperationState {
            return HomeStatus(
                title: "Sync needs another look",
                message: message,
                isProblem: true,
                action: summary.retryableUploadCount > 0
                    ? .retry
                    : .sync("Try Sync Again")
            )
        }
        if summary.pendingUploadCount > 0 {
            let count = summary.pendingUploadCount
            return HomeStatus(
                title: "\(count) upload\(count == 1 ? "" : "s") waiting",
                message: "The local copies are safe.",
                action: summary.retryableUploadCount > 0
                    ? .retry
                    : .sync("Sync Now")
            )
        }
        if model.syncReadiness == .healthReviewRecommended {
            return HomeStatus(
                title: "Apple Health access needs review",
                message: "Readable types keep syncing.",
                action: .sync("Sync Now")
            )
        }
        if case .healthStatusUnavailable(canSync: true) = model.syncReadiness {
            return HomeStatus(
                title: "Apple Health status could not be refreshed",
                message: "Previously readable data keeps syncing.",
                action: .sync("Sync Now")
            )
        }
        if summary.lastSuccessfulSyncAt == nil {
            return HomeStatus(
                title: "Ready for the first sync",
                message: "HealthMule exports one JSON file per day to your Drive.",
                action: .sync("Sync Now")
            )
        }
        return HomeStatus(
            title: "Up to date",
            message: "Recent changes and missing days are checked on every sync.",
            action: .sync("Sync Now")
        )
    }

    private static func setupStatus(_ readiness: SyncReadiness) -> HomeStatus? {
        switch readiness {
        case .localStorageUnavailable:
            HomeStatus(
                title: "Local storage is unavailable",
                message: "HealthMule could not prepare its protected staging area, so syncing is paused.",
                isProblem: true
            )
        case .checkingConnections:
            HomeStatus(
                title: "Checking connections",
                message: "Restoring Apple Health and Google authorization."
            )
        case .healthUnavailable:
            HomeStatus(
                title: "Apple Health is unavailable",
                message: "HealthMule needs an iPhone with Apple Health.",
                isProblem: true
            )
        case .healthStatusUnavailable(canSync: false):
            HomeStatus(
                title: "Apple Health status is unavailable",
                message: "Check Apple Health again below."
            )
        case .healthRequestRequired:
            HomeStatus(
                title: "Finish setup",
                message: "Request read-only Apple Health access below."
            )
        case .googleNotConfigured:
            HomeStatus(
                title: "Google is not configured",
                message: "Add the OAuth client to Config/Secrets.xcconfig and rebuild.",
                isProblem: true
            )
        case .googleDisconnected:
            HomeStatus(
                title: "Finish setup",
                message: "Connect the Google Drive account that will own the export."
            )
        case .googleTemporarilyUnavailable:
            HomeStatus(
                title: "Google is temporarily unavailable",
                message: "Local records are safe. Try again below."
            )
        case .googleReauthorizationRequired:
            HomeStatus(
                title: "Google Drive needs approval",
                message: "Reconnect below to resume pending uploads.",
                isProblem: true
            )
        case .googleDriveSetupRequired:
            HomeStatus(
                title: "Preparing your Drive folder",
                message: "Google is authorized; the export folder is being verified."
            )
        case .googleDriveUnavailable:
            HomeStatus(
                title: "Drive folder needs a retry",
                message: "Local records are safe. Try Drive again below.",
                isProblem: true
            )
        case .healthStatusUnavailable(canSync: true),
             .healthReviewRecommended,
             .ready:
            nil
        }
    }
}
