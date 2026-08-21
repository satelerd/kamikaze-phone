import ClerkKit
import Foundation

/// Public client configuration for optional cloud identity. Local play never
/// depends on these values; a missing configuration simply keeps the account
/// surface in guest mode.
@MainActor
enum KamikazeIdentityConfiguration {
    static let clerk: Clerk? = {
        guard let publishableKey = configuredString(named: "KamikazeClerkPublishableKey"),
              publishableKey.hasPrefix("pk_") else {
            return nil
        }
        return Clerk.configure(publishableKey: publishableKey)
    }()

    static var convexDeploymentURL: String? {
        guard let host = configuredString(named: "KamikazeConvexDeploymentHost"),
              host.contains("."),
              !host.contains("REPLACE_ME") else {
            return nil
        }
        return "https://\(host)"
    }

    static var isConfigured: Bool {
        clerk != nil
    }

    static var hasActiveUser: Bool {
        clerk?.user != nil
    }

    private static func bundleString(named key: String) -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    private static func configuredString(named key: String) -> String? {
        if let bundled = bundleString(named: key) {
            return bundled
        }
        guard let url = Bundle.main.url(
            forResource: "KamikazeAuth.local",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
        let rawValue = object[key] else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
