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
    @Test("recognizes a compound Phone Flip while preserving transparent alternatives")
    func phoneFlipTopThree() throws {
        let result = TrickMatcher().match(
            attempt: makeAttempt(
                rotationDegrees: Vector3(x: 0, y: 490, z: 0),
                durationS: 1.0,
                cancellingPathDegrees: Vector3(x: 300, y: 0, z: 200)
            ),
            catalog: .provisional(gripHand: .right)
        )

        #expect(result.status == .recognized)
        #expect(result.candidates.count == 3)
        #expect(result.candidates.first?.definition.id == .phoneFlip)
        #expect(result.candidates.first?.presentationFit ?? 0 >= 0.75)
        #expect(result.policyVersion.contains("angular-path"))
        #expect(result.catalogVersion.contains("iphone15plus-right"))
    }

    @Test("recognizes the physically calibrated full rotation as a 360 Shuvit")
    func noisyHalfShuvit() {
        let result = TrickMatcher().match(
            attempt: makeAttempt(
                rotationDegrees: Vector3(x: 12, y: 45, z: 335),
                durationS: 0.72,
                cancellingPathDegrees: Vector3(x: 120, y: 120, z: 0)
            ),
            catalog: .provisional(gripHand: .right)
        )

        #expect(result.candidates.first?.definition.id == .backsideThreeSixtyShuvit)
        #expect(result.status == .recognized)
        #expect(result.candidates.first?.definition.family == .shuvit)
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
        let attempt = makeAttempt(rotationDegrees: Vector3(x: 0, y: 0, z: 335), durationS: 0.72)
        let right = TrickMatcher().match(attempt: attempt, catalog: .provisional(gripHand: .right))
        let left = TrickMatcher().match(attempt: attempt, catalog: .provisional(gripHand: .left))

        #expect(right.candidates.first?.definition.id == .backsideThreeSixtyShuvit)
        #expect(left.candidates.first?.definition.id == .frontsideThreeSixtyShuvit)
        #expect(try #require(right.features).signedRotationDegrees == left.features?.signedRotationDegrees)
    }

    @Test("legacy Shuvit identifiers decode as the calibrated 360 variants")
    func legacyShuvitNamesKeepTheirPhysicalMeaning() throws {
        let backside = try JSONDecoder().decode(
            BuiltInTrickID.self,
            from: Data("\"backside-shuvit\"".utf8)
        )
        let frontside = try JSONDecoder().decode(
            BuiltInTrickID.self,
            from: Data("\"frontside-shuvit\"".utf8)
        )

        #expect(backside == .backsideThreeSixtyShuvit)
        #expect(frontside == .frontsideThreeSixtyShuvit)
        #expect(BuiltInTrickID.backsideShuvit.rawValue == "backside-shuvit-180")
        #expect(BuiltInTrickID.frontsideShuvit.rawValue == "frontside-shuvit-180")
    }

    @Test("pure Y rotation is a Flip, not a Phone Flip")
    func axialFlipDoesNotCollapseIntoPhoneFlip() {
        let result = TrickMatcher().match(
            attempt: makeAttempt(rotationDegrees: Vector3(x: 0, y: 370, z: 0), durationS: 0.82),
            catalog: .provisional(gripHand: .right)
        )

        #expect(result.candidates.first?.definition.id == .flip)
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

    @Test("sample gaps can never produce a recognized result")
    func gappedEvidenceNeedsReview() {
        let attempt = makeAttempt(
            rotationDegrees: Vector3(x: 0, y: 360, z: 0),
            durationS: 0.78,
            qualityAtMiddle: [.timestampGapBefore, .sequenceGapBefore]
        )
        let result = TrickMatcher().match(
            attempt: attempt,
            catalog: .provisional(gripHand: .right)
        )

        #expect(result.candidates.first?.definition.id == .flip)
        #expect(result.status == .review)
        #expect(result.featureIssues.contains(.timestampGap))
        #expect(result.featureIssues.contains(.sequenceGap))
    }

    @Test("v0.1 persisted results decode without angular-path fields")
    func legacyResultRemainsDecodable() throws {
        let result = TrickMatcher().match(
            attempt: makeAttempt(rotationDegrees: Vector3(x: 0, y: 370, z: 0)),
            catalog: .provisional(gripHand: .right)
        )
        let encoded = try JSONEncoder().encode(result)
        var root = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var candidates = try #require(root["candidates"] as? [[String: Any]])
        for index in candidates.indices {
            candidates[index].removeValue(forKey: "pathProfileFit")
            var definition = try #require(candidates[index]["definition"] as? [String: Any])
            definition.removeValue(forKey: "targetAngularPathShare")
            if definition["id"] as? String == "flip" {
                definition["id"] = "front-flip"
            }
            candidates[index]["definition"] = definition
        }
        root["candidates"] = candidates
        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(TrickMatchResult.self, from: legacyData)

        #expect(decoded.candidates.count == result.candidates.count)
        #expect(decoded.candidates.first?.pathProfileFit == nil)
        #expect(decoded.candidates.first?.definition.targetAngularPathShare == nil)
        #expect(decoded.candidates.first?.definition.id == .flip)
    }
}

private func makeAttempt(
    rotationDegrees: Vector3,
    durationS: Double = 0.62,
    catchAccelerationG: Double = 1,
    qualityAtMiddle: MotionSampleQualityFlags = [],
    cancellingPathDegrees: Vector3 = Vector3(x: 0, y: 0, z: 0)
) -> SegmentedAttemptV3 {
    let stepCount = 100
    let deltaTimeS = durationS / Double(stepCount)
    let baseRateDps = Vector3(
        x: rotationDegrees.x / durationS,
        y: rotationDegrees.y / durationS,
        z: rotationDegrees.z / durationS
    )
    var attitude = Quaternion.identity
    var samples: [MotionSampleV3] = []
    for index in 0...stepCount {
        let cancellationSign = index <= stepCount / 2 ? 1.0 : -1.0
        let rateDps = Vector3(
            x: baseRateDps.x + cancellationSign * cancellingPathDegrees.x / durationS,
            y: baseRateDps.y + cancellationSign * cancellingPathDegrees.y / durationS,
            z: baseRateDps.z + cancellationSign * cancellingPathDegrees.z / durationS
        )
        let rateRadS = Vector3(
            x: rateDps.x * .pi / 180,
            y: rateDps.y * .pi / 180,
            z: rateDps.z * .pi / 180
        )
        if index > 0 {
            attitude = QuaternionMath.integrated(attitude, rotationRateDps: rateDps, deltaTimeS: deltaTimeS)
        }
        samples.append(MotionSampleV3(
            sequence: UInt64(index),
            timestampS: Double(index) * deltaTimeS,
            rotationRateRadS: rateRadS,
            userAccelerationG: Vector3(x: 0, y: 0, z: -0.7),
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: attitude,
            qualityFlags: index == stepCount / 2 ? qualityAtMiddle : []
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
