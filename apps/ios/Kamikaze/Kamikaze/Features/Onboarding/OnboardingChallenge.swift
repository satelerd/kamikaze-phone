import Foundation
import KamikazeMotionCore

/// Authored order for the first-run story. The last two steps deliberately
/// split LEARN from TRY: a player sees the exact Shuvit motion before the app
/// asks the detector to judge it.
nonisolated enum OnboardingStep: Int, CaseIterable, Equatable, Sendable {
    case board
    case safety
    case origin
    case straightAir
    case shuvitLearn
    case shuvitTry

    var position: Int { rawValue + 1 }
    var isSensorChallenge: Bool { self == .straightAir || self == .shuvitTry }
}

nonisolated enum OnboardingChallengeEvaluator {
    /// Ballistic estimate from the measured low-g window. This is a tutorial
    /// threshold, not a claim that the IMU observes absolute position.
    static let minimumStraightAirHeightM = 0.30
    static let firstShuvit: BuiltInTrickID = .backsideShuvit

    static func passesStraightAir(estimatedHeightM: Double?) -> Bool {
        guard let estimatedHeightM, estimatedHeightM.isFinite else { return false }
        return estimatedHeightM >= minimumStraightAirHeightM
    }

    static func passesShuvit(
        status: TrickRecognitionStatus,
        trickID: BuiltInTrickID?
    ) -> Bool {
        status == .recognized && trickID == firstShuvit
    }
}
