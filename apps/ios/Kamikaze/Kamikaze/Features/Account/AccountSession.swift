import Foundation
import Observation

/// Account operations stay behind this seam so Clerk is an integration detail
/// rather than a requirement for local play, previews or unit tests.
@MainActor
protocol AccountSession: AnyObject {
    var snapshot: AccountSnapshot { get }

    func refresh() async
    func signInWithApple() async throws
    func presentAuth(_ route: AccountAuthRoute) async throws
    func signOut() async throws
    func requestDeleteAccount() async throws
}

@MainActor
@Observable
final class AccountViewModel {
    private let session: any AccountSession

    private(set) var snapshot: AccountSnapshot
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    init(session: any AccountSession) {
        self.session = session
        self.snapshot = session.snapshot
    }

    func refresh() async {
        await session.refresh()
        snapshot = session.snapshot
    }

    func signInWithApple() async {
        await run {
            try await session.signInWithApple()
        }
    }

    func presentAuth(_ route: AccountAuthRoute) async {
        await run {
            try await session.presentAuth(route)
        }
    }

    func signOut() async {
        await run {
            try await session.signOut()
        }
    }

    func requestDeleteAccount() async {
        await run {
            try await session.requestDeleteAccount()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func run(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            try await operation()
            snapshot = session.snapshot
        } catch let error as AccountSessionError {
            errorMessage = error.localizedDescription
            snapshot = session.snapshot
        } catch {
            errorMessage = error.localizedDescription
            snapshot = session.snapshot
        }
    }
}

/// Used by the app until the publishable key is supplied. It never pretends
/// that a button press created an identity.
@MainActor
final class UnconfiguredAccountSession: AccountSession {
    private(set) var snapshot: AccountSnapshot = .signedOut

    func refresh() async {}

    func signInWithApple() async throws {
        throw AccountSessionError.clerkNotConfigured
    }

    func presentAuth(_ route: AccountAuthRoute) async throws {
        throw AccountSessionError.clerkNotConfigured
    }

    func signOut() async throws {
        snapshot = .signedOut
    }

    func requestDeleteAccount() async throws {
        throw AccountSessionError.deletionNotAvailable
    }
}

/// Deterministic state machine for previews and tests. The mock has no network
/// behavior and can only move to snapshots supplied by the caller.
@MainActor
final class MockAccountSession: AccountSession {
    private(set) var snapshot: AccountSnapshot
    let appleSignInSnapshot: AccountSnapshot?
    let authSnapshot: AccountSnapshot?
    private(set) var lastRequestedAuthRoute: AccountAuthRoute?

    init(
        snapshot: AccountSnapshot = .signedOut,
        appleSignInSnapshot: AccountSnapshot? = .previewSignedIn,
        authSnapshot: AccountSnapshot? = .previewSignedIn
    ) {
        self.snapshot = snapshot
        self.appleSignInSnapshot = appleSignInSnapshot
        self.authSnapshot = authSnapshot
    }

    func refresh() async {}

    func signInWithApple() async throws {
        guard let appleSignInSnapshot else {
            throw AccountSessionError.operationFailed("APPLE SIGN-IN IS DISABLED IN THIS PREVIEW.")
        }
        snapshot = appleSignInSnapshot
    }

    func presentAuth(_ route: AccountAuthRoute) async throws {
        lastRequestedAuthRoute = route
        guard let authSnapshot else {
            throw AccountSessionError.operationFailed("AUTH IS DISABLED IN THIS PREVIEW.")
        }
        snapshot = authSnapshot
    }

    func signOut() async throws {
        snapshot = .signedOut
    }

    func requestDeleteAccount() async throws {
        throw AccountSessionError.deletionNotAvailable
    }
}
