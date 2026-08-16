import Foundation
import KamikazeMotionCore

/// Lightweight, versioned projection of one attempt for lists and statistics.
/// It is derived from attempt metadata plus the stored analysis record and can
/// always be rebuilt from them; raw samples are never required to display it.
nonisolated struct AttemptSummaryV1: Codable, Equatable, Sendable, Identifiable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let attemptID: String
    let recordedAtISO8601: String
    /// Timezone the capture was summarized in. Legacy attempts predate this
    /// field, so statistics must treat `nil` as "device timezone, assumed".
    let timezoneIdentifier: String?
    /// Displayed identity after any human override. Canonical IDs only; legacy
    /// Shuvit spellings are canonicalized by `BuiltInTrickID` when decoding.
    let trickID: BuiltInTrickID?
    let recognitionStatus: TrickRecognitionStatus
    let humanOutcome: HumanAttemptOutcome?
    let motionDurationMs: Double
    /// Identity FIT of the displayed candidate in [0, 1]. Not a probability,
    /// landing quality or game score.
    let fit: Double?
    /// Intentionally nil until a versioned Game Score exists.
    let gameScore: Int?
    let analysisVersion: String
    let catalogVersion: String
    let sampleCount: Int

    var id: String { attemptID }

    var interpretationSource: AttemptInterpretationSource {
        humanOutcome == nil ? .detector : .human
    }

    var hasConfirmedLanding: Bool { humanOutcome == .landed }

    /// Display success — what the player's counters celebrate. The human
    /// verdict always wins when present; an unreviewed attempt counts
    /// through the detector's recognized identity. NEEDS REVIEW and UNKNOWN
    /// therefore read as misses until a review says otherwise.
    var countsAsSuccess: Bool {
        if let humanOutcome { return humanOutcome == .landed }
        return recognitionStatus == .recognized
    }

    /// Counts toward "Recognized": detector identity, or a valid human trick
    /// correction. A `noAttempt` review removes the attempt from recognition.
    var isRecognized: Bool {
        if let humanOutcome {
            return humanOutcome != .noAttempt && trickID != nil
        }
        return recognitionStatus == .recognized
    }

    var displayName: String {
        if let trickID { return trickID.displayName }
        if humanOutcome == .noAttempt { return "NO ATTEMPT" }
        switch recognitionStatus {
        case .recognized: return "REVIEW THROW"
        case .review: return "NEEDS REVIEW"
        case .unknown, .invalid: return "UNKNOWN THROW"
        }
    }

    var outcomeLabel: String {
        humanOutcome?.displayName ?? recognitionStatus.rawValue.uppercased()
    }

    init(
        attempt: MotionAttemptV3,
        analysis: AttemptAnalysisRecord,
        timezone: TimeZone? = nil
    ) {
        let review = analysis.humanReview
        let displayedTrick: BuiltInTrickID?
        if let review {
            displayedTrick = review.outcome == .noAttempt ? nil : review.trickID
        } else {
            switch analysis.result.status {
            case .recognized:
                displayedTrick = analysis.result.candidates.first?.definition.id
            case .review, .unknown, .invalid:
                displayedTrick = nil
            }
        }

        let displayedCandidate: TrickMatchCandidate?
        if let reviewedTrick = review?.trickID {
            displayedCandidate = analysis.result.candidates.first { $0.definition.id == reviewedTrick }
        } else {
            displayedCandidate = analysis.result.candidates.first
        }

        self.schemaVersion = Self.schemaVersion
        self.attemptID = attempt.id
        self.recordedAtISO8601 = attempt.recordedAtISO8601
        self.timezoneIdentifier = timezone?.identifier
        self.trickID = displayedTrick
        self.recognitionStatus = analysis.result.status
        self.humanOutcome = review?.outcome
        self.motionDurationMs = analysis.result.features?.motionDurationMs
            ?? (attempt.boundaries.motionEndS - attempt.boundaries.motionStartS) * 1_000
        self.fit = displayedCandidate?.presentationFit
        self.gameScore = nil
        self.analysisVersion = analysis.result.policyVersion
        self.catalogVersion = analysis.result.catalogVersion
        self.sampleCount = attempt.rawSamples.sampleCount
    }
}
