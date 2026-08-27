import Foundation
import KamikazeMotionCore

/// Community trick definitions describe rider intent, not detector math.
/// A published proposal can collect evidence without being inserted into the
/// frozen detector catalog.
nonisolated struct CommunityTrickProposal: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: String
    let creatorID: String
    var name: String
    var description: String
    var coachingCue: String
    var aliases: [String]
    var status: CommunityTrickProposalStatus
    let createdAtISO8601: String
    var updatedAtISO8601: String

    init(
        id: String = UUID().uuidString.lowercased(),
        creatorID: String,
        name: String,
        description: String,
        coachingCue: String,
        aliases: [String] = [],
        status: CommunityTrickProposalStatus = .draft,
        createdAt: Date = Date()
    ) {
        let timestamp = ISO8601DateFormatter().string(from: createdAt)
        self.schemaVersion = Self.schemaVersion
        self.id = id
        self.creatorID = creatorID
        self.name = name.normalizedCommunityText
        self.description = description.normalizedCommunityText
        self.coachingCue = coachingCue.normalizedCommunityText
        self.aliases = aliases.normalizedCommunityAliases
        self.status = status
        self.createdAtISO8601 = timestamp
        self.updatedAtISO8601 = timestamp
    }

    var isValidDraft: Bool {
        schemaVersion == Self.schemaVersion
            && id.isCommunitySafeIdentifier
            && creatorID.isCommunitySafeIdentifier
            && (3 ... 60).contains(name.count)
            && (3 ... 280).contains(description.count)
            && (3 ... 140).contains(coachingCue.count)
            && aliases.count <= 12
            && aliases.allSatisfy { (2 ... 60).contains($0.count) }
    }
}

nonisolated enum CommunityTrickProposalStatus: String, Codable, Equatable, Sendable {
    case draft
    case submitted
    case published
    case rejected
}

/// Review identity is advisory in the local prototype. A future cloud
/// mutation must derive `role` from the authenticated server session rather
/// than accepting it from the client.
nonisolated struct CommunityTrickActor: Codable, Equatable, Sendable {
    let id: String
    let role: CommunityTrickActorRole

    init(id: String, role: CommunityTrickActorRole = .rider) {
        self.id = id
        self.role = role
    }
}

nonisolated enum CommunityTrickActorRole: String, Codable, Equatable, Sendable {
    case rider
    case moderator
}

nonisolated struct CommunityProposalReview: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let proposalID: String
    let reviewerID: String
    let decision: CommunityReviewDecision
    let notes: String
    let reviewedAtISO8601: String
}

nonisolated enum CommunityReviewDecision: String, Codable, Equatable, Sendable {
    case approved
    case rejected
}

/// Points to immutable sensor evidence without duplicating it into the social
/// record. The checksum lets a later export/upload verify the exact payload.
nonisolated struct CommunityMotionEvidenceReference: Codable, Equatable, Sendable {
    let attemptID: String
    let localResourceID: String
    let payloadSchemaVersion: Int
    let sampleCount: Int
    let checksum: String
    let detectorVersionAtCapture: String

    init(
        attemptID: String,
        localResourceID: String,
        payloadSchemaVersion: Int,
        sampleCount: Int,
        checksum: String,
        detectorVersionAtCapture: String
    ) {
        self.attemptID = attemptID
        self.localResourceID = localResourceID
        self.payloadSchemaVersion = payloadSchemaVersion
        self.sampleCount = sampleCount
        self.checksum = checksum
        self.detectorVersionAtCapture = detectorVersionAtCapture
    }

    init(capture: MotionCaptureV3, localResourceID: String) {
        self.init(
            attemptID: capture.attempt.id,
            localResourceID: localResourceID,
            payloadSchemaVersion: capture.attempt.rawSamples.payloadSchemaVersion,
            sampleCount: capture.attempt.rawSamples.sampleCount,
            checksum: capture.attempt.rawSamples.checksum,
            detectorVersionAtCapture: capture.attempt.versions.detectorVersion
        )
    }

    var isValid: Bool {
        attemptID.isCommunitySafeIdentifier
            && !localResourceID.normalizedCommunityText.isEmpty
            && payloadSchemaVersion > 0
            && sampleCount > 0
            && checksum.count >= 32
            && !detectorVersionAtCapture.normalizedCommunityText.isEmpty
    }
}

nonisolated struct CommunityTrickExample: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: String
    let proposalID: String
    let contributorID: String
    let evidence: CommunityMotionEvidenceReference
    var outcome: CommunityTrickExampleOutcome
    var notes: String
    var status: CommunityTrickExampleStatus
    let createdAtISO8601: String
    var updatedAtISO8601: String

    init(
        id: String = UUID().uuidString.lowercased(),
        proposalID: String,
        contributorID: String,
        evidence: CommunityMotionEvidenceReference,
        outcome: CommunityTrickExampleOutcome,
        notes: String = "",
        status: CommunityTrickExampleStatus = .draft,
        createdAt: Date = Date()
    ) {
        let timestamp = ISO8601DateFormatter().string(from: createdAt)
        self.schemaVersion = Self.schemaVersion
        self.id = id
        self.proposalID = proposalID
        self.contributorID = contributorID
        self.evidence = evidence
        self.outcome = outcome
        self.notes = notes.normalizedCommunityText
        self.status = status
        self.createdAtISO8601 = timestamp
        self.updatedAtISO8601 = timestamp
    }

    var isValid: Bool {
        schemaVersion == Self.schemaVersion
            && id.isCommunitySafeIdentifier
            && proposalID.isCommunitySafeIdentifier
            && contributorID.isCommunitySafeIdentifier
            && evidence.isValid
            && notes.count <= 500
    }
}

nonisolated enum CommunityTrickExampleOutcome: String, Codable, Equatable, Sendable {
    case landed
    case missed
    case noAttempt
    case unclear

    /// Ambiguous labels are useful as drafts, but are never training evidence.
    var isReviewableEvidence: Bool { self != .unclear }
}

nonisolated enum CommunityTrickExampleStatus: String, Codable, Equatable, Sendable {
    case draft
    case submitted
    case approved
    case rejected
}

nonisolated struct CommunityExampleReview: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let exampleID: String
    let proposalID: String
    let reviewerID: String
    let decision: CommunityReviewDecision
    let notes: String
    let reviewedAtISO8601: String
}

/// An eligibility record, not a model update. Offline training/evaluation can
/// consume these references later and must still apply split, consent,
/// integrity and holdout policy.
nonisolated struct CommunityTrainingEvidence: Codable, Equatable, Identifiable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: String
    let proposalID: String
    let exampleID: String
    let evidence: CommunityMotionEvidenceReference
    let outcome: CommunityTrickExampleOutcome
    let contributorID: String
    let approvedByID: String
    let approvedAtISO8601: String
    let detectorVersionAtPromotion: String
    let trainingState: CommunityTrainingEvidenceState
}

nonisolated enum CommunityTrainingEvidenceState: String, Codable, Equatable, Sendable {
    /// Available to export for an offline dataset audit. It has not trained or
    /// changed any on-device matcher.
    case eligibleForOfflineReview
}

nonisolated struct CommunityTrickSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    var proposals: [CommunityTrickProposal]
    var proposalReviews: [CommunityProposalReview]
    var examples: [CommunityTrickExample]
    var exampleReviews: [CommunityExampleReview]
    var trainingEvidence: [CommunityTrainingEvidence]

    init(
        proposals: [CommunityTrickProposal] = [],
        proposalReviews: [CommunityProposalReview] = [],
        examples: [CommunityTrickExample] = [],
        exampleReviews: [CommunityExampleReview] = [],
        trainingEvidence: [CommunityTrainingEvidence] = []
    ) {
        self.schemaVersion = Self.schemaVersion
        self.proposals = proposals
        self.proposalReviews = proposalReviews
        self.examples = examples
        self.exampleReviews = exampleReviews
        self.trainingEvidence = trainingEvidence
    }

    static let empty = Self()
}

private extension String {
    nonisolated var normalizedCommunityText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    nonisolated var isCommunitySafeIdentifier: Bool {
        !isEmpty && count <= 128
            && allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

private extension Array where Element == String {
    nonisolated var normalizedCommunityAliases: [String] {
        var seen = Set<String>()
        return compactMap { alias -> String? in
            let normalized = alias.normalizedCommunityText
            let key = normalized.lowercased()
            guard !normalized.isEmpty, seen.insert(key).inserted else { return nil }
            return normalized
        }
    }
}
