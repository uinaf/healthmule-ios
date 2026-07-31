import Foundation

struct GoogleOAuthConfiguration: Equatable, Sendable {
    let clientID: String
    let redirectScheme: String

    var isConfigured: Bool {
        let clientIDSuffix = ".apps.googleusercontent.com"
        guard
            clientID.hasSuffix(clientIDSuffix),
            clientID.count > clientIDSuffix.count,
            !redirectScheme.hasSuffix("-example")
        else {
            return false
        }
        let clientPrefix = clientID.dropLast(clientIDSuffix.count)
        return redirectScheme
            == "com.googleusercontent.apps.\(clientPrefix)"
    }

    static func bundled(bundle: Bundle = .main) -> GoogleOAuthConfiguration {
        GoogleOAuthConfiguration(
            clientID: bundle.object(forInfoDictionaryKey: "GIDClientID") as? String ?? "",
            redirectScheme: (
                bundle.object(forInfoDictionaryKey: "CFBundleURLTypes")
                    as? [[String: Any]]
            )?
                .compactMap { $0["CFBundleURLSchemes"] as? [String] }
                .flatMap { $0 }
                .first ?? ""
        )
    }
}
