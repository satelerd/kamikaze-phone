import Foundation
import KamikazeMotionCore

/// Versioned, deterministic gameplay score. This is deliberately separate
/// from trick identity: the matcher answers "what motion was this?", while
/// this score describes how completely and cleanly that proposed motion was
/// executed. It is not a probability or a trained landing classifier.
nonisolated enum AttemptScoreVerification: String, Codable, Equatable, Sendable {
    case automaticProvisional
    case humanLanded
    case humanMissed

    var label: String {
        switch self {
        case .automaticProvisional: "PROVISIONAL"
        case .humanLanded: "LANDED"
        case .humanMissed: "MISSED"
        }
    }
}

typealias AttemptScoreComponents = MotionQualityComponents

nonisolated struct AttemptGameScore: Codable, Equatable, Sendable {
    let value: Int
    let version: String
    let verification: AttemptScoreVerification
    let components: AttemptScoreComponents
}

nonisolated enum GameScoreEngine {
    static let version = "game-score-v1-\(MotionQualityScorer.version)"

    static func evaluate(
        match: TrickMatchResult,
        humanReview: HumanAttemptReview?
    ) -> AttemptGameScore? {
        let selectedTrick = humanReview?.trickID ?? match.candidates.first?.definition.id
        guard let selectedTrick else { return nil }

        let verification: AttemptScoreVerification
        if let outcome = humanReview?.outcome {
            switch outcome {
            case .landed:
                verification = .humanLanded
            case .missed:
                verification = .humanMissed
            case .unclear, .noAttempt:
                return nil
            }
        } else {
            // A review/unknown identity must not quietly become a gameplay
            // score. The player can confirm it without altering raw evidence.
            guard match.status == .recognized else { return nil }
            verification = .automaticProvisional
        }

        guard let motionQuality = MotionQualityScorer.score(
            match: match,
            selectedTrickID: selectedTrick
        ) else { return nil }
        let value = verification == .humanMissed
            ? 0
            : motionQuality.value

        return AttemptGameScore(
            value: value,
            version: version,
            verification: verification,
            components: motionQuality.components
        )
    }
}
