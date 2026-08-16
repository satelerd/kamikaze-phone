import Testing
@testable import KamikazeMotionCore

struct MotionQualityScorerTests {
    @Test("scores transparent components without using duration")
    func deterministicComponents() throws {
        let score = try #require(MotionQualityScorer.score(
            match: match(durationFit: 0),
            selectedTrickID: .flip
        ))
        let second = try #require(MotionQualityScorer.score(
            match: match(durationFit: 1),
            selectedTrickID: .flip
        ))

        #expect(score.value == 79)
        #expect(score.components == MotionQualityComponents(
            completion: 0.9,
            purity: 0.8,
            stability: 0.75,
            flow: 0.6
        ))
        #expect(second == score)
    }

    @Test("hard evidence gaps cannot produce a score")
    func rejectsEvidenceGap() {
        var result = match(durationFit: 0.8)
        result = TrickMatchResult(
            status: result.status,
            policyVersion: result.policyVersion,
            catalogVersion: result.catalogVersion,
            features: result.features,
            featureIssues: [.sequenceGap],
            candidates: result.candidates
        )
        #expect(MotionQualityScorer.score(match: result, selectedTrickID: .flip) == nil)
    }

    @Test("selected identity must exist in retained candidates")
    func requiresSelectedCandidate() {
        #expect(MotionQualityScorer.score(
            match: match(durationFit: 0.8),
            selectedTrickID: .reverseFlip
        ) == nil)
    }

    private func match(durationFit: Double) -> TrickMatchResult {
        let definition = TrickDefinition(
            id: .flip,
            displayName: "FLIP",
            family: .flip,
            targetRotationDegrees: Vector3(x: 0, y: 360, z: 0),
            referenceDurationMs: 800
        )
        return TrickMatchResult(
            status: .recognized,
            policyVersion: "test",
            catalogVersion: "test",
            features: MotionFeatures(
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
            ),
            featureIssues: [],
            candidates: [TrickMatchCandidate(
                definition: definition,
                presentationFit: 0.84,
                rotationFit: 0.9,
                axisPurity: 0.8,
                durationFit: durationFit,
                pathProfileFit: 0.8,
                minimumAxisCoverage: 0.9,
                axesAreSeparable: true
            )]
        )
    }
}
