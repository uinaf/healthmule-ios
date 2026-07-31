import GoogleSignIn
import UIKit

enum GoogleAuthError: LocalizedError, Equatable, Sendable {
    case configurationMissing
    case presenterUnavailable
    case signedOut
    case scopeNotGranted
    case identityUnavailable
    case accountChanged
    case reauthorizationRequired
    case refreshTemporarilyUnavailable

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            "Google OAuth is not configured yet."
        case .presenterUnavailable:
            "Google Sign-In could not find a window to present from."
        case .signedOut:
            "Connect Google before syncing."
        case .scopeNotGranted:
            "Google Drive access was not granted. Reconnect and allow file access."
        case .identityUnavailable:
            "Google account identity could not be verified. Reconnect your account."
        case .accountChanged:
            "The active Google account changed. The upload will be retried for the current account."
        case .reauthorizationRequired:
            "Google Drive access needs approval. Reconnect your account."
        case .refreshTemporarilyUnavailable:
            "Google authorization could not be refreshed yet. The upload will be retried."
        }
    }
}

@MainActor
final class GoogleAuthService {
    static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    private let configuration: GoogleOAuthConfiguration

    init(configuration: GoogleOAuthConfiguration) {
        self.configuration = configuration
    }

    var isConfigured: Bool {
        configuration.isConfigured
    }

    func restore() async throws -> GoogleConnectionState {
        guard isConfigured else {
            return .notConfigured
        }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            guard user.grantedScopes?.contains(Self.driveFileScope) == true else {
                throw GoogleAuthError.scopeNotGranted
            }
            guard let userID = user.userID, !userID.isEmpty else {
                throw GoogleAuthError.identityUnavailable
            }
            return .authorized(
                GoogleAccount(
                    id: userID,
                    email: user.profile?.email
                )
            )
        } catch let error as GoogleAuthError {
            throw error
        } catch {
            let error = error as NSError
            if
                error.domain == "com.google.GIDSignIn",
                error.code == -4
            {
                return .disconnected
            }
            throw Self.refreshError(for: error)
        }
    }

    func connect() async throws -> GoogleConnectionState {
        guard isConfigured else {
            throw GoogleAuthError.configurationMissing
        }
        guard let presenter = Self.presentingViewController() else {
            throw GoogleAuthError.presenterUnavailable
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: [Self.driveFileScope]
        )
        guard result.user.grantedScopes?.contains(Self.driveFileScope) == true else {
            throw GoogleAuthError.scopeNotGranted
        }
        guard let userID = result.user.userID, !userID.isEmpty else {
            throw GoogleAuthError.identityUnavailable
        }
        return .authorized(
            GoogleAccount(
                id: userID,
                email: result.user.profile?.email
            )
        )
    }

    func accessToken(for expectedAccountID: String) async throws -> String {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleAuthError.signedOut
        }
        guard currentUser.userID == expectedAccountID else {
            throw GoogleAuthError.accountChanged
        }
        guard currentUser.grantedScopes?.contains(Self.driveFileScope) == true else {
            throw GoogleAuthError.scopeNotGranted
        }
        do {
            let refreshedUser = try await currentUser.refreshTokensIfNeeded()
            guard
                refreshedUser.userID == expectedAccountID,
                GIDSignIn.sharedInstance.currentUser?.userID
                    == expectedAccountID
            else {
                throw GoogleAuthError.accountChanged
            }
            return refreshedUser.accessToken.tokenString
        } catch let error as GoogleAuthError {
            throw error
        } catch {
            throw Self.refreshError(for: error)
        }
    }

    func disconnect() async throws {
        guard GIDSignIn.sharedInstance.currentUser != nil else { return }
        try await GIDSignIn.sharedInstance.disconnect()
    }

    nonisolated static func refreshError(for error: Error) -> GoogleAuthError {
        let error = error as NSError
        if error.domain == "org.openid.appauth.oauth_token" {
            return .reauthorizationRequired
        }
        if
            error.domain == "com.google.GIDSignIn",
            [-2, -4, -9].contains(error.code)
        {
            return .reauthorizationRequired
        }
        if
            containsNetworkError(error)
                || (
                    error.domain == "org.openid.appauth.general"
                        && [-5, -6].contains(error.code)
                )
        {
            return .refreshTemporarilyUnavailable
        }
        return .refreshTemporarilyUnavailable
    }

    nonisolated private static func containsNetworkError(
        _ error: NSError
    ) -> Bool {
        if error.domain == NSURLErrorDomain {
            return true
        }
        guard let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        else {
            return false
        }
        return containsNetworkError(underlying)
    }

    private static func presentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let root = scenes
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        return topViewController(from: root)
    }

    private static func topViewController(
        from viewController: UIViewController?
    ) -> UIViewController? {
        if let navigation = viewController as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = viewController as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = viewController?.presentedViewController {
            return topViewController(from: presented)
        }
        return viewController
    }
}
