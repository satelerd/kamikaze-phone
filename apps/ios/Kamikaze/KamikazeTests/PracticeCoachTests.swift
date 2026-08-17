import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct PracticeCoachTests {
    private func features(
        signed: Vector3,
        path: Vector3
    ) -> MotionFeatures {
        MotionFeatures(
            motionDurationMs: 700,
            signedRotationDegrees: signed,
            angularPathDegrees: path,
            totalAngularPathDegrees: path.x + path.y + path.z,
            fusedAttitudeRotationDegrees: nil,
            gyroFusedAgreement: nil,
            fusedComparisonSampleCount: 0,
            peakGyroDps: 600,
            minimumAccelerationG: nil,
            peakAccelerationG: nil,
            peakCatchAccelerationG: nil,
            postCatchStability: 0.05,
            dominantAxisPurity: 0.8,
            rotationEfficiency: 0.9
        )
    }

    private func definition(_ target: Vector3) -> TrickDefinition {
        TrickDefinition(
            id: .flip,
            displayName: "TEST",
            family: .flip,
            targetRotationDegrees: target,
            referenceDurationMs: 700
        )
    }

    @Test func shortRotationOnDominantAxisIsTheFirstCue() {
        let cue = PracticeCoach.primaryCue(
            features: features(
                signed: Vector3(x: 4, y: 328, z: -8),
                path: Vector3(x: 30, y: 360, z: 30)
            ),
            definition: definition(Vector3(x: 0, y: 370, z: 0))
        )
        #expect(cue == "42° SHORT ON THE FLIP AXIS")
    }

    @Test func overRotationReadsAsOver() {
        let cue = PracticeCoach.primaryCue(
            features: features(
                signed: Vector3(x: 0, y: 0, z: -412),
                path: Vector3(x: 20, y: 30, z: 420)
            ),
            definition: definition(Vector3(x: 0, y: 0, z: -360))
        )
        #expect(cue == "52° OVER ON THE SPIN AXIS")
    }

    @Test func cleanExecutionGetsNoCue() {
        let cue = PracticeCoach.primaryCue(
            features: features(
                signed: Vector3(x: 2, y: 366, z: -5),
                path: Vector3(x: 40, y: 380, z: 35)
            ),
            definition: definition(Vector3(x: 0, y: 370, z: 0))
        )
        #expect(cue == nil)
    }

    @Test func offAxisContaminationIsCalledOutWhenCompletionIsFine() {
        let cue = PracticeCoach.primaryCue(
            features: features(
                signed: Vector3(x: 6, y: 12, z: -352),
                path: Vector3(x: 40, y: 210, z: 380)
            ),
            definition: definition(Vector3(x: 0, y: 0, z: -360))
        )
        #expect(cue == "TOO MUCH FLIP-AXIS MOTION")
    }

    @Test func missingFeaturesStaySilent() {
        #expect(PracticeCoach.primaryCue(features: nil, definition: definition(Vector3(x: 0, y: 370, z: 0))) == nil)
    }

    @Test func reviewMessagePrioritizesIdentityBeforeAxisAdvice() {
        let target = definition(Vector3(x: 0, y: 370, z: 0))
        #expect(PracticeCoach.reviewMessage(
            features: nil,
            definition: target,
            recognizedTrickID: nil
        ) == "NO CLEAR MATCH — REPLAY IT, THEN TRY ONE CLEAN ROTATION")
        #expect(PracticeCoach.reviewMessage(
            features: nil,
            definition: target,
            recognizedTrickID: .reverseFlip
        ) == "DETECTOR SAW REVERSE FLIP — CHECK THE TARGET DIRECTION")
    }

    @Test func cleanOnTargetReviewGetsPositiveInstruction() {
        let target = definition(Vector3(x: 0, y: 370, z: 0))
        let message = PracticeCoach.reviewMessage(
            features: features(
                signed: Vector3(x: 2, y: 366, z: -5),
                path: Vector3(x: 40, y: 380, z: 35)
            ),
            definition: target,
            recognizedTrickID: .flip
        )
        #expect(message == "CLEAN ROTATION — REPEAT THAT MOTION")
    }
}
