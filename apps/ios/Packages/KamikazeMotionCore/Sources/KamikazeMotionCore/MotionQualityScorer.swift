import Foundation

/// Versioned, deterministic motion-quality reduction. It deliberately knows
/// nothing about human landing verdicts or awarded game points; the app layer
/// applies those policies after this pure evidence calculation.
public struct MotionQualityComponents: Codable, Equatable, Sendable {
    public let completion: Double
    public let purity: Double
    public let stability: Double
    public let flow: Double

    public init(completion: Double, purity: Double, stability: Double, flow: Double) {
        self.completion = completion
        self.purity = purity
        self.stability = stability
        self.flow = flow
    }
}

public struct MotionQualityScore: Codable, Equatable, Sendable {
    public let value: Int
    public let components: MotionQualityComponents

    public init(value: Int, components: MotionQualityComponents) {
        self.value = value
        self.components = components
    }
}

public enum MotionQualityScorer {
    public static let version = "motion-quality-v1"

    public static func score(
        match: TrickMatchResult,
        selectedTrickID: BuiltInTrickID
    ) -> MotionQualityScore? {
        guard evidenceIsScoreable(match),
              let candidate = match.candidates.first(where: { $0.definition.id == selectedTrickID }),
              let features = match.features,
              let stability = features.postCatchStability else {
            return nil
        }

        let components = MotionQualityComponents(
            completion: clamp((candidate.rotationFit + candidate.minimumAxisCoverage) / 2),
            purity: clamp(candidate.pathProfileFit ?? candidate.axisPurity),
            stability: clamp(stability),
            flow: clamp(features.rotationEfficiency)
        )
        // Duration is intentionally excluded: fast/low and high throws are
        // valid styles, not execution defects.
        let value = components.completion * 0.35
            + components.purity * 0.20
            + components.stability * 0.30
            + components.flow * 0.15
        return MotionQualityScore(
            value: Int((clamp(value) * 100).rounded()),
            components: components
        )
    }

    private static func evidenceIsScoreable(_ match: TrickMatchResult) -> Bool {
        let invalidating: [MotionFeatureIssue] = [
            .invalidBoundaries,
            .insufficientMotionSamples,
            .nonFiniteEvidence,
            .nonMonotonicTimestamp,
            .timedOutSegmentation,
            .timestampGap,
            .sequenceGap,
            .fusedAttitudeUnavailable,
            .partialFusedAttitude,
        ]
        return match.features != nil
            && !match.featureIssues.contains(where: invalidating.contains)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
