import Foundation
import KamikazeMotionCore

/// The cloud projection deliberately contains no raw motion samples. Local
/// AttemptSummaryV1 remains the source of truth for offline play; this type is
/// only the bounded metadata sent to Convex.
nonisolated struct CloudAttemptSummaryV1: Codable, Equatable, Sendable, Identifiable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let attemptID: String
    let recordedAtISO8601: String
    let timezoneIdentifier: String?
    let trickID: String?
    let recognitionStatus: String
    let humanOutcome: String?
    let motionDurationMs: Double
    let fit: Double?
    let gameScore: Int?
    let scoreVersion: String?
    let analysisVersion: String
    let catalogVersion: String
    let sampleCount: Int

    var id: String { attemptID }

    init(
        attemptID: String,
        recordedAtISO8601: String,
        timezoneIdentifier: String? = nil,
        trickID: String? = nil,
        recognitionStatus: String,
        humanOutcome: String? = nil,
        motionDurationMs: Double,
        fit: Double? = nil,
        gameScore: Int? = nil,
        scoreVersion: String? = nil,
        analysisVersion: String,
        catalogVersion: String,
        sampleCount: Int
    ) {
        self.schemaVersion = Self.schemaVersion
        self.attemptID = attemptID
        self.recordedAtISO8601 = recordedAtISO8601
        self.timezoneIdentifier = timezoneIdentifier
        self.trickID = trickID
        self.recognitionStatus = recognitionStatus
        self.humanOutcome = humanOutcome
        self.motionDurationMs = motionDurationMs
        self.fit = fit
        self.gameScore = gameScore
        self.scoreVersion = scoreVersion
        self.analysisVersion = analysisVersion
        self.catalogVersion = catalogVersion
        self.sampleCount = sampleCount
    }

    /// Adapter kept here so the main agent can enqueue an existing local
    /// summary without changing the existing Persistence files.
    init(local summary: AttemptSummaryV1) {
        self.init(
            attemptID: summary.attemptID,
            recordedAtISO8601: summary.recordedAtISO8601,
            timezoneIdentifier: summary.timezoneIdentifier,
            trickID: summary.trickID?.rawValue,
            recognitionStatus: summary.recognitionStatus.rawValue,
            humanOutcome: summary.humanOutcome?.rawValue,
            motionDurationMs: summary.motionDurationMs,
            fit: summary.fit,
            gameScore: summary.gameScore,
            scoreVersion: summary.scoreVersion,
            analysisVersion: summary.analysisVersion,
            catalogVersion: summary.catalogVersion,
            sampleCount: summary.sampleCount
        )
    }
}

nonisolated enum CloudVisibility: String, Codable, CaseIterable, Equatable, Sendable {
    case `private`
    case friends
    case `public`
}

nonisolated struct CloudProfilePatch: Codable, Equatable, Sendable {
    let displayName: String
    let joinedAtISO8601: String
    let bio: String?
    let profileVisibility: CloudVisibility
}

nonisolated enum CloudMediaKind: String, Codable, Equatable, Sendable {
    case replay
    case thumbnail
    case avatar
}

nonisolated struct CloudMediaRegistration: Codable, Equatable, Sendable {
    let mediaKey: String
    let attemptID: String?
    let kind: CloudMediaKind
    let storageID: String
    let contentType: String
    let byteSize: Int
    let sha256: String?
    let visibility: CloudVisibility
}

nonisolated enum CloudSyncOperationKind: String, Codable, Equatable, Sendable {
    case upsertProfile
    case upsertAttemptSummary
    case registerMedia
    case setSocialVisibility
    case deleteAttemptSummary
    case deleteMedia
    case deleteAccount
}

/// A serializable outbox command. Optional members are intentionally omitted
/// from Convex arguments when nil because `v.optional(...)` accepts an absent
/// field, not JSON null.
nonisolated struct CloudSyncOperation: Codable, Equatable, Sendable {
    let kind: CloudSyncOperationKind
    let profile: CloudProfilePatch?
    let attemptSummary: CloudAttemptSummaryV1?
    let media: CloudMediaRegistration?
    let attemptID: String?
    let mediaKey: String?
    let visibility: CloudVisibility?

    static func upsertProfile(_ profile: CloudProfilePatch) -> Self {
        Self(kind: .upsertProfile, profile: profile)
    }

    static func upsertAttemptSummary(_ summary: CloudAttemptSummaryV1) -> Self {
        Self(kind: .upsertAttemptSummary, attemptSummary: summary)
    }

    static func registerMedia(_ media: CloudMediaRegistration) -> Self {
        Self(kind: .registerMedia, media: media)
    }

    static func setSocialVisibility(attemptID: String, visibility: CloudVisibility) -> Self {
        Self(kind: .setSocialVisibility, attemptID: attemptID, visibility: visibility)
    }

    static func deleteAttemptSummary(attemptID: String) -> Self {
        Self(kind: .deleteAttemptSummary, attemptID: attemptID)
    }

    static func deleteMedia(mediaKey: String) -> Self {
        Self(kind: .deleteMedia, mediaKey: mediaKey)
    }

    static func deleteAccount() -> Self {
        Self(kind: .deleteAccount)
    }

    init(
        kind: CloudSyncOperationKind,
        profile: CloudProfilePatch? = nil,
        attemptSummary: CloudAttemptSummaryV1? = nil,
        media: CloudMediaRegistration? = nil,
        attemptID: String? = nil,
        mediaKey: String? = nil,
        visibility: CloudVisibility? = nil
    ) {
        self.kind = kind
        self.profile = profile
        self.attemptSummary = attemptSummary
        self.media = media
        self.attemptID = attemptID
        self.mediaKey = mediaKey
        self.visibility = visibility
    }

    nonisolated var functionName: String {
        switch kind {
        case .upsertProfile: "profiles:upsertMine"
        case .upsertAttemptSummary: "attemptSummaries:upsert"
        case .registerMedia: "media:register"
        case .setSocialVisibility: "social:setVisibility"
        case .deleteAttemptSummary: "attemptSummaries:deleteMine"
        case .deleteMedia: "media:deleteMine"
        case .deleteAccount: "users:deleteMyAccount"
        }
    }

    nonisolated func arguments(mutationID: String) throws -> CloudArguments {
        var values: CloudArguments = ["mutationID": .string(mutationID)]
        switch kind {
        case .upsertProfile:
            guard let profile else { throw CloudSyncError.invalidOperation("Profile payload missing") }
            values["displayName"] = .string(profile.displayName)
            values["joinedAtISO8601"] = .string(profile.joinedAtISO8601)
            values["profileVisibility"] = .string(profile.profileVisibility.rawValue)
            if let bio = profile.bio { values["bio"] = .string(bio) }
        case .upsertAttemptSummary:
            guard let summary = attemptSummary else {
                throw CloudSyncError.invalidOperation("Attempt summary payload missing")
            }
            values["attemptID"] = .string(summary.attemptID)
            values["recordedAtISO8601"] = .string(summary.recordedAtISO8601)
            if let timezoneIdentifier = summary.timezoneIdentifier {
                values["timezoneIdentifier"] = .string(timezoneIdentifier)
            }
            if let trickID = summary.trickID { values["trickID"] = .string(trickID) }
            values["recognitionStatus"] = .string(summary.recognitionStatus)
            if let humanOutcome = summary.humanOutcome {
                values["humanOutcome"] = .string(humanOutcome)
            }
            values["motionDurationMs"] = .number(summary.motionDurationMs)
            if let fit = summary.fit { values["fit"] = .number(fit) }
            if let gameScore = summary.gameScore { values["gameScore"] = .number(Double(gameScore)) }
            if let scoreVersion = summary.scoreVersion { values["scoreVersion"] = .string(scoreVersion) }
            values["analysisVersion"] = .string(summary.analysisVersion)
            values["catalogVersion"] = .string(summary.catalogVersion)
            values["sampleCount"] = .number(Double(summary.sampleCount))
        case .registerMedia:
            guard let media else { throw CloudSyncError.invalidOperation("Media payload missing") }
            values["mediaKey"] = .string(media.mediaKey)
            if let attemptID = media.attemptID { values["attemptID"] = .string(attemptID) }
            values["kind"] = .string(media.kind.rawValue)
            values["storageId"] = .string(media.storageID)
            values["contentType"] = .string(media.contentType)
            values["byteSize"] = .number(Double(media.byteSize))
            if let sha256 = media.sha256 { values["sha256"] = .string(sha256) }
            values["visibility"] = .string(media.visibility.rawValue)
        case .setSocialVisibility:
            guard let attemptID, let visibility else {
                throw CloudSyncError.invalidOperation("Social visibility payload missing")
            }
            values["attemptID"] = .string(attemptID)
            values["visibility"] = .string(visibility.rawValue)
        case .deleteAttemptSummary:
            guard let attemptID else { throw CloudSyncError.invalidOperation("Attempt ID missing") }
            values["attemptID"] = .string(attemptID)
        case .deleteMedia:
            guard let mediaKey else { throw CloudSyncError.invalidOperation("Media key missing") }
            values["mediaKey"] = .string(mediaKey)
        case .deleteAccount:
            break
        }
        return values
    }
}

nonisolated enum CloudSyncError: Error, Equatable, Sendable {
    case invalidOperation(String)
    case invalidMutationID
    case mutationIDCollision
    case ioFailure(String)
    case notConfigured
    case unauthenticated
    case unavailable(String)
}
