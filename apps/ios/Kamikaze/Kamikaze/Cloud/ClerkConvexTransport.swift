import Foundation

/// Authenticated bridge between Clerk and Convex. The imports remain
/// conditional so previews and lightweight package tests can still compile
/// without pulling the application-only SDKs into the motion core.
#if canImport(ClerkConvex) && canImport(ConvexMobile)
import Combine
import ClerkConvex
import ClerkKit
@preconcurrency import ConvexMobile

@MainActor
final class ClerkConvexTransport: ConvexTransport {
    let client: ConvexClientWithAuth<String>

    /// `Clerk.configure(publishableKey:)` must run before this initializer.
    /// The publishable key is safe for the client; no Clerk secret key or
    /// Convex deploy key belongs in the iOS target.
    init(deploymentURL: String) {
        self.client = ConvexClientWithAuth(
            deploymentUrl: deploymentURL,
            authProvider: ClerkConvexAuthProvider()
        )
    }

    var authState: AnyPublisher<AuthState<String>, Never> {
        client.authState
    }

    /// Use this after Clerk has loaded a previously persisted session. Clerk's
    /// adapter obtains and refreshes the JWT; the app never handles a secret.
    @discardableResult
    func loginFromCache() async -> Result<String, Error> {
        await client.loginFromCache()
    }

    /// Use this when the user completes an interactive Clerk sign-in.
    @discardableResult
    func login() async -> Result<String, Error> {
        await client.login()
    }

    func logout() async {
        await client.logout()
    }

    @MainActor
    func query<Value: Decodable & Sendable>(
        _ function: String,
        arguments: CloudArguments,
        as type: Value.Type
    ) async throws -> Value {
        let publisher = client.subscribe(
            to: function,
            with: convexArguments(arguments),
            yielding: type
        )
        for try await value in publisher.values {
            return value
        }
        throw CloudSyncError.unavailable("Convex query ended without a value")
    }

    @MainActor
    func mutation<Value: Decodable & Sendable>(
        _ function: String,
        arguments: CloudArguments,
        as type: Value.Type
    ) async throws -> Value {
        do {
            return try await client.mutation(
                function,
                with: convexArguments(arguments)
            )
        } catch {
            throw mapConvexError(error)
        }
    }

    /// Convex's async mutation is `@concurrent` in Swift 6. Build its
    /// package-shaped dictionary in a nonisolated helper so the value is not
    /// considered a MainActor-owned result when it crosses that boundary.
    nonisolated private func convexArguments(_ arguments: CloudArguments) -> [String: ConvexEncodable?] {
        arguments.mapValues { value in
            Optional(value as any ConvexEncodable)
        }
    }

    private func mapConvexError(_ error: Error) -> Error {
        // ConvexMobile intentionally exposes provider/server errors as a
        // library-specific enum. Keep the mapping conservative: only errors
        // that clearly indicate missing auth become a retryable auth state;
        // all other details stay local and are not logged with token data.
        let description = String(describing: error).lowercased()
        if description.contains("unauthenticated") ||
            description.contains("not authenticated") ||
            description.contains("unauthorized") ||
            description.contains("401") {
            return CloudSyncError.unauthenticated
        }
        return error
    }
}

@MainActor
extension ConvexCloudClient {
    /// Creates the existing domain client over the one process-lifetime
    /// authenticated Convex client. `Clerk.configure` is intentionally kept
    /// at the app composition boundary because this Cloud layer must not own
    /// publishable-key loading or auth UI.
    static func clerk(deploymentURL: String) -> (
        remote: ConvexCloudClient,
        transport: ClerkConvexTransport
    ) {
        let transport = ClerkConvexTransport(deploymentURL: deploymentURL)
        return (
            remote: ConvexCloudClient(transport: transport),
            transport: transport
        )
    }
}

nonisolated extension CloudJSONValue: ConvexEncodable {
    public func convexEncode() throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: foundationValue,
            options: [.fragmentsAllowed, .sortedKeys]
        )
        guard let result = String(data: data, encoding: .utf8) else {
            throw CloudSyncError.unavailable("Convex argument encoding failed")
        }
        return result
    }
}
#endif
