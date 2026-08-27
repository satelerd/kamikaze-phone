import Foundation

/// The small identity projection the Me surface needs.  Clerk's complete
/// `User` object never crosses into the social/account UI, which keeps the
/// feature easy to preview and keeps future Convex payloads display-safe.
nonisolated struct AccountIdentity: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let emailAddress: String?
    let imageURL: URL?
    let provider: AccountIdentityProvider
    let isEmailVerified: Bool

    init(
        id: String,
        displayName: String,
        emailAddress: String? = nil,
        imageURL: URL? = nil,
        provider: AccountIdentityProvider = .clerk,
        isEmailVerified: Bool = false
    ) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "KAMIKAZE RIDER"
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.emailAddress = emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.imageURL = imageURL
        self.provider = provider
        self.isEmailVerified = isEmailVerified
    }

    var initials: String {
        let words = displayName.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters = words.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "K" : result
    }

    var accessibilitySummary: String {
        var parts = [displayName]
        if let emailAddress, !emailAddress.isEmpty { parts.append(emailAddress) }
        if isEmailVerified { parts.append("email verified") }
        return parts.joined(separator: ", ")
    }
}

nonisolated enum AccountIdentityProvider: String, Codable, Equatable, Sendable {
    case clerk
    case apple
    case email
    case unknown

    var title: String {
        switch self {
        case .clerk: "CLERK ACCOUNT"
        case .apple: "APPLE ACCOUNT"
        case .email: "EMAIL ACCOUNT"
        case .unknown: "ACCOUNT"
        }
    }
}

nonisolated enum AccountPhase: String, Codable, Equatable, Sendable {
    case loading
    case signedOut
    case signedIn
    case failed
}

nonisolated enum AccountAuthRoute: String, Codable, CaseIterable, Equatable, Hashable, Sendable, Identifiable {
    case signInOrUp
    case signIn
    case signUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signInOrUp: "SIGN IN OR SIGN UP"
        case .signIn: "SIGN IN"
        case .signUp: "SIGN UP"
        }
    }
}

nonisolated enum AccountSyncState: String, Codable, Equatable, Sendable {
    case localOnly
    case ready
    case syncing
    case needsAuthentication
    case unavailable
    case failed

    var title: String {
        switch self {
        case .localOnly: "LOCAL ONLY"
        case .ready: "SYNC READY"
        case .syncing: "SYNCING"
        case .needsAuthentication: "AUTH NEEDED"
        case .unavailable: "SYNC UNAVAILABLE"
        case .failed: "SYNC PAUSED"
        }
    }

    var iconName: String {
        switch self {
        case .localOnly: "iphone"
        case .ready: "checkmark.shield"
        case .syncing: "arrow.triangle.2.circlepath"
        case .needsAuthentication: "person.badge.key"
        case .unavailable: "icloud.slash"
        case .failed: "exclamationmark.triangle"
        }
    }
}

nonisolated struct AccountSyncSnapshot: Codable, Equatable, Sendable {
    let state: AccountSyncState
    let detail: String
    let lastSyncedAt: Date?

    init(
        state: AccountSyncState,
        detail: String,
        lastSyncedAt: Date? = nil
    ) {
        self.state = state
        self.detail = detail
        self.lastSyncedAt = lastSyncedAt
    }

    static let localOnly = AccountSyncSnapshot(
        state: .localOnly,
        detail: "Nothing leaves this phone until you choose to share it."
    )

    static let ready = AccountSyncSnapshot(
        state: .ready,
        detail: "Account connected. Private sync can be enabled next."
    )
}

nonisolated struct AccountSnapshot: Codable, Equatable, Sendable {
    let phase: AccountPhase
    let identity: AccountIdentity?
    let sync: AccountSyncSnapshot
    /// Account deletion remains a deliberate future operation until the
    /// product's retention policy and backend mutation are connected.
    let canRequestDeletion: Bool

    init(
        phase: AccountPhase,
        identity: AccountIdentity? = nil,
        sync: AccountSyncSnapshot = .localOnly,
        canRequestDeletion: Bool = false
    ) {
        self.phase = phase
        self.identity = identity
        self.sync = sync
        self.canRequestDeletion = canRequestDeletion
    }

    static let loading = AccountSnapshot(phase: .loading, sync: .localOnly)
    static let signedOut = AccountSnapshot(phase: .signedOut, sync: .localOnly)

    static let previewSignedIn = AccountSnapshot(
        phase: .signedIn,
        identity: AccountIdentity(
            id: "preview-user",
            displayName: "MARA ROJAS",
            emailAddress: "mara@example.com",
            provider: .clerk,
            isEmailVerified: true
        ),
        sync: .ready
    )
}

nonisolated enum AccountSessionError: Error, Equatable, Sendable, LocalizedError {
    case clerkNotConfigured
    case operationFailed(String)
    case deletionNotAvailable

    var errorDescription: String? {
        switch self {
        case .clerkNotConfigured:
            "ACCOUNT SETUP NEEDED · Add the Clerk publishable key to enable sign-in."
        case let .operationFailed(message):
            message
        case .deletionNotAvailable:
            "ACCOUNT DELETION WILL BE AVAILABLE AFTER THE RETENTION POLICY IS CONNECTED."
        }
    }
}
