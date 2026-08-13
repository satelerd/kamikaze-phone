import Foundation
import Testing
@testable import KamikazeMotionCore

@Suite("Motion feature extraction")
struct MotionFeatureExtractorTests {
    @Test("integrates signed gyro and path while cross-checking fused attitude")
    func extractsUnitExplicitFeatures() throws {
        let attempt = makeAttempt(
            rotationDegrees: Vector3(x: 0, y: 360, z: 0),
            durationS: 0.72,
            catchAccelerationG: 2.4
        )
        let extraction = MotionFeatureExtractor.extract(from: attempt)
        let features = try #require(extraction.features)

        #expect(abs(features.signedRotationDegrees.y - 360) < 0.001)
        #expect(abs(features.angularPathDegrees.y - 360) < 0.001)
        #expect(abs(features.totalAngularPathDegrees - 360) < 0.001)
        #expect(abs((features.fusedAttitudeRotationDegrees?.y ?? 0) - 360) < 0.01)
        #expect((features.gyroFusedAgreement ?? 0) > 0.999)
        #expect(features.fusedComparisonSampleCount == 100)
        #expect(abs(features.motionDurationMs - 720) < 0.001)
        #expect(abs(features.peakGyroDps - 500) < 0.001)
        #expect(features.peakCatchAccelerationG == 2.4)
        #expect((features.postCatchStability ?? 0) > 0.75)
        #expect(features.dominantAxisPurity == 1)
        #expect(features.rotationEfficiency == 1)
    }

    @Test("rejects non-monotonic motion evidence instead of silently sorting it")
    func invalidTimestampEvidence() {
        var attempt = makeAttempt(rotationDegrees: Vector3(x: 360, y: 0, z: 0))
        let duplicated = MotionSampleV3(
            sequence: 1,
            timestampS: attempt.samples[0].timestampS,
            rotationRateRadS: attempt.samples[1].rotationRateRadS,
            userAccelerationG: Vector3(x: 0, y: 0, z: -0.7),
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: attempt.samples[1].fusedAttitude ?? .identity
        )
        var samples = attempt.samples
        samples[1] = duplicated
        attempt = SegmentedAttemptV3(
            captureMode: attempt.captureMode,
            trigger: attempt.trigger,
            boundaries: attempt.boundaries,
            samples: samples,
            timedOut: false
        )

        let extraction = MotionFeatureExtractor.extract(from: attempt)
        #expect(extraction.features == nil)
        #expect(extraction.issues == [.nonMonotonicTimestamp])
    }
}

@Suite("Provisional trick catalog matcher")
struct TrickMatcherTests {
    @Test("returns a recognized Phone Flip plus two transparent alternatives")
    func phoneFlipTopThree() throws {
        let result = TrickMatcher().match(
            attempt: makeAttempt(rotationDegrees: Vector3(x: 4, y: 360, z: 6), durationS: 0.78),
            catalog: .provisional(gripHand: .right)
        )

        #expect(result.status == .recognized)
        #expect(result.candidates.count == 3)
        #expect(result.candidates.first?.definition.id == .phoneFlip)
        #expect(result.candidates.first?.presentationFit ?? 0 >= 0.75)
        #expect(result.policyVersion.contains("uncalibrated"))
        #expect(result.catalogVersion.contains("uncalibrated"))
    }

    @Test("does not promote a noisy half shuvit to a 360 combo")
    func noisyHalfShuvit() {
        let result = TrickMatcher().match(
            attempt: makeAttempt(rotationDegrees: Vector3(x: 12, y: 200, z: 185), durationS: 0.52),
            catalog: .provisional(gripHand: .right)
        )

        #expect(result.candidates.first?.definition.id == .backsideShuvit)
        #expect(result.status == .recognized)
        let combo = result.candidates.first { $0.definition.id == .threeSixtyFlip }
        #expect(combo == nil || combo?.axesAreSeparable == false)
    }

    @Test("malformed partial front rotation abstains instead of forcing a label")
    func malformedFrontAbstains() {
        let result = TrickMatcher().match(
            attempt: makeAttempt(rotationDegrees: Vector3(x: 225, y: 35, z: 150), durationS: 0.62),
            catalog: .provisional(gripHand: .right)
        )

        #expect(result.status == .review || result.status == .unknown)
        #expect(result.status != .recognized)
    }

    @Test("left grip mirrors Y and Z names without changing raw features")
    func gripMirror() throws {
        let attempt = makeAttempt(rotationDegrees: Vector3(x: 0, y: 0, z: 180), durationS: 0.52)
        let right = TrickMatcher().match(attempt: attempt, catalog: .provisional(gripHand: .right))
        let left = TrickMatcher().match(attempt: attempt, catalog: .provisional(gripHand: .left))

        #expect(right.candidates.first?.definition.id == .backsideShuvit)
        #expect(left.candidates.first?.definition.id == .frontsideShuvit)
        #expect(try #require(right.features).signedRotationDegrees == left.features?.signedRotationDegrees)
    }

    @Test("combo wins only when both axes are independently covered")
    func separableCombo() {
        let result = TrickMatcher().match(
            attempt: makeAttempt(rotationDegrees: Vector3(x: 0, y: 360, z: 360), durationS: 0.82),
            catalog: .provisional(gripHand: .right)
        )

        #expect(result.candidates.first?.definition.id == .threeSixtyFlip)
        #expect(result.candidates.first?.axesAreSeparable == true)
        #expect(result.status == .recognized)
    }

    @Test("invalid evidence returns invalid with no invented candidates")
    func invalidEvidence() {
        let empty = SegmentedAttemptV3(
            captureMode: .manual,
            trigger: .manual,
            boundaries: AttemptBoundariesV3(
                captureStartS: 1,
                captureEndS: 1,
                motionStartS: 1,
                motionEndS: 1,
                releaseS: nil,
                catchS: nil,
                settledS: nil
            ),
            samples: [],
            timedOut: false
        )
        let result = TrickMatcher().match(attempt: empty, catalog: .provisional(gripHand: .right))

        #expect(result.status == .invalid)
        #expect(result.candidates.isEmpty)
        #expect(result.featureIssues == [.invalidBoundaries])
    }
}

private func makeAttempt(
    rotationDegrees: Vector3,
    durationS: Double = 0.62,
    catchAccelerationG: Double = 1
) -> SegmentedAttemptV3 {
    let stepCount = 100
    let deltaTimeS = durationS / Double(stepCount)
    let rateDps = Vector3(
        x: rotationDegrees.x / durationS,
        y: rotationDegrees.y / durationS,
        z: rotationDegrees.z / durationS
    )
    let rateRadS = Vector3(
        x: rateDps.x * .pi / 180,
        y: rateDps.y * .pi / 180,
        z: rateDps.z * .pi / 180
    )
    var attitude = Quaternion.identity
    var samples: [MotionSampleV3] = []
    for index in 0...stepCount {
        if index > 0 {
            attitude = QuaternionMath.integrated(attitude, rotationRateDps: rateDps, deltaTimeS: deltaTimeS)
        }
        samples.append(MotionSampleV3(
            sequence: UInt64(index),
            timestampS: Double(index) * deltaTimeS,
            rotationRateRadS: rateRadS,
            userAccelerationG: Vector3(x: 0, y: 0, z: -0.7),
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: attitude
        ))
    }

    for index in 1...10 {
        let accelerationG = index == 1 ? catchAccelerationG : 1
        samples.append(MotionSampleV3(
            sequence: UInt64(stepCount + index),
            timestampS: durationS + Double(index) * 0.01,
            rotationRateRadS: Vector3(x: 0, y: 0, z: 0),
            userAccelerationG: Vector3(x: 0, y: 0, z: accelerationG - 1),
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: attitude
        ))
    }

    return SegmentedAttemptV3(
        captureMode: .auto,
        trigger: .gyro,
        boundaries: AttemptBoundariesV3(
            captureStartS: 0,
            captureEndS: durationS + 0.1,
            motionStartS: 0,
            motionEndS: durationS,
            releaseS: nil,
            catchS: durationS,
            settledS: durationS + 0.1
        ),
        samples: samples,
        timedOut: false
    )
}
