import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct GameScoreEngineTests {
    @Test func recognizedAttemptGetsDeterministicProvisionalScore() {
        let score = GameScoreEngine.evaluate(match: match(status: .recognized), humanReview: nil)

        #expect(score?.version == GameScoreEngine.version)
        #expect(score?.verification == .automaticProvisional)
        // 0.90 completion, 0.80 purity, 0.75 stability, 0.60 flow.
        #expect(score?.value == 79)
    }

    @Test func reviewIdentityDoesNotBecomeAutomaticScore() {
        #expect(GameScoreEngine.evaluate(match: match(status: .review), humanReview: nil) == nil)
    }

    @Test func humanLandingCanScoreReviewIdentity() {
        let review = HumanAttemptReview(trickID: .flip, outcome: .landed)
        let score = GameScoreEngine.evaluate(match: match(status: .review), humanReview: review)

        #expect(score?.value == 79)
        #expect(score?.verification == .humanLanded)
    }

    @Test func humanMissAwardsZeroWithoutErasingMeasuredComponents() {
        let review = HumanAttemptReview(trickID: .flip, outcome: .missed)
        let score = GameScoreEngine.evaluate(match: match(status: .recognized), humanReview: review)

        #expect(score?.value == 0)
        #expect(score?.verification == .humanMissed)
        #expect(score?.components.completion == 0.9)
    }

    @Test func corruptedTimingCannotProduceScore() {
        let result = match(status: .recognized, issues: [.timestampGap])
        let review = HumanAttemptReview(trickID: .flip, outcome: .landed)

        #expect(GameScoreEngine.evaluate(match: result, humanReview: review) == nil)
    }

    private func match(
        status: TrickRecognitionStatus,
        issues: [MotionFeatureIssue] = []
    ) -> TrickMatchResult {
        let definition = TrickDefinition(
            id: .flip,
            displayName: "FLIP",
            family: .flip,
            targetRotationDegrees: Vector3(x: 0, y: 360, z: 0),
            referenceDurationMs: 800
        )
        let candidate = TrickMatchCandidate(
            definition: definition,
            presentationFit: 0.84,
            rotationFit: 0.9,
            axisPurity: 0.8,
            durationFit: 0.4,
            pathProfileFit: 0.8,
            minimumAxisCoverage: 0.9,
            axesAreSeparable: true
        )
        let features = MotionFeatures(
            motionDurationMs: 650,
            signedRotationDegrees: Vector3(x: 0, y: 360, z: 0),
            angularPathDegrees: Vector3(x: 30, y: 390, z: 20),
            totalAngularPathDegrees: 440,
            fusedAttitudeRotationDegrees: Vector3(x: 0, y: 358, z: 0),
            gyroFusedAgreement: 0.98,
            fusedComparisonSampleCount: 40,
            peakGyroDps: 1_000,
            minimumAccelerationG: 0.2,
            peakAccelerationG: 4,
            peakCatchAccelerationG: 3,
            postCatchStability: 0.75,
            dominantAxisPurity: 0.8,
            rotationEfficiency: 0.6
        )
        return TrickMatchResult(
            status: status,
            policyVersion: "test",
            catalogVersion: "test",
            features: features,
            featureIssues: issues,
            candidates: [candidate]
        )
    }
}
