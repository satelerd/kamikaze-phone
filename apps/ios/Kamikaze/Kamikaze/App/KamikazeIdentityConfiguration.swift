import ClerkKit
import Foundation

/// Public client configuration for optional cloud identity. Local play never
/// depends on these values; a missing configuration simply keeps the account
/// surface in guest mode.
@MainActor
enum KamikazeIdentityConfiguration {
    static let clerk: Clerk? = {
        guard let publishableKey = bundleString(named: "KamikazeClerkPublishableKey"),
              publishableKey.hasPrefix("pk_") else {
            return nil
        }
        return Clerk.configure(publishableKey: publishableKey)
    }()

    static var convexDeploymentURL: String? {
        guard let host = bundleString(named: "KamikazeConvexDeploymentHost"),
              host.contains("."),
              !host.contains("REPLACE_ME") else {
            return nil
        }
        return "https://\(host)"
    }

    static var isConfigured: Bool {
        clerk != nil
    }

    private static func bundleString(named key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
