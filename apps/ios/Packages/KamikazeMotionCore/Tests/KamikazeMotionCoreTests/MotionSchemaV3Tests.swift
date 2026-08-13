import Foundation
import Testing
@testable import KamikazeMotionCore

@Suite("Native motion schema v3")
struct MotionSchemaV3Tests {
    private struct FixtureCase {
        let file: String
        let expectedTrick: String
        let sampleCount: Int
        let checksum: String
    }

    private let fixtures = [
        FixtureCase(
            file: "iphone15plus-right-phone-flip-001.json",
            expectedTrick: "PHONE FLIP",
            sampleCount: 202,
            checksum: "9645219974ae7f74872f8a72d8241dfb94c01238f32fba8a95feeaa5d3dd26ff"
        ),
        FixtureCase(
            file: "iphone15plus-right-reverse-phone-flip-001.json",
            expectedTrick: "REVERSE PHONE FLIP",
            sampleCount: 217,
            checksum: "a5bd90e12e3261b12ae315d66b2f6ee96ea749b967f64eb4d627092c6aac6a84"
        ),
    ]

    @Test("native samples retain raw unit-explicit Core Motion evidence")
    func nativeSampleRoundTrip() throws {
        let sample = MotionSampleV3(
            sequence: 42,
            timestampS: 123.456,
            rotationRateRadS: Vector3(x: 1.5, y: -2, z: 0.25),
            userAccelerationG: Vector3(x: 0.1, y: -0.2, z: 0.3),
            gravityG: Vector3(x: 0, y: 0, z: -1),
            fusedAttitude: Quaternion(w: 0.9, x: 0.1, y: 0.2, z: 0.3),
            qualityFlags: [.timestampGapBefore]
        )

        let encoded = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(MotionSampleV3.self, from: encoded)

        #expect(decoded == sample)
        #expect(decoded.sequence == 42)
        #expect(decoded.rotationRateRadS == Vector3(x: 1.5, y: -2, z: 0.25))
        #expect(decoded.fusedAttitude == Quaternion(w: 0.9, x: 0.1, y: 0.2, z: 0.3))
        #expect(decoded.accelerationIncludingGravityG == Vector3(x: 0.1, y: -0.2, z: -0.7))
        #expect(decoded.qualityFlags.contains(.timestampGapBefore))
        #expect(decoded.legacyAccelerationIncludingGravityG == nil)
    }

    @Test("both real Expo fixtures migrate without fabricating missing evidence")
    func migratesRealExpoFixtures() throws {
        for fixture in fixtures {
            let labelled = try decodeFixture(named: fixture.file)
            let legacy = labelled.recordedAttempt
            let capture = try ExpoAttemptV2Migration.convert(
                legacy,
                context: migrationContext(for: fixture)
            )

            #expect(labelled.expectedTrick == fixture.expectedTrick)
            #expect(capture.attempt.schemaVersion == MotionSchemaV3.version)
            #expect(capture.attempt.id == legacy.id)
            #expect(capture.attempt.captureMode == .manual)
            #expect(capture.attempt.environment.device.modelName == "iPhone 15 Plus")
            #expect(capture.attempt.environment.device.operatingSystemVersion == nil)
            #expect(capture.attempt.environment.gripHand == .right)
            #expect(capture.attempt.environment.orientation == .unknown)
            #expect(capture.attempt.environment.requestedFrequencyHz == 100)
            #expect(abs((capture.attempt.environment.measuredFrequencyHz ?? 0) - 100.3) < 0.02)
            #expect(capture.attempt.versions.detectorVersion == "expo-alpha-v2")
            #expect(capture.attempt.versions.scoreVersion == nil)
            #expect(capture.attempt.rawSamples.checksum == fixture.checksum)
            #expect(capture.attempt.rawSamples.sampleCount == fixture.sampleCount)
            #expect(capture.samplePayload.schemaVersion == MotionSchemaV3.version)
            #expect(capture.samplePayload.attemptID == legacy.id)
            #expect(capture.samplePayload.samples.count == fixture.sampleCount)
            #expect(capture.attempt.importedExpoAnalysis?.trick == legacy.trick)
            #expect(capture.attempt.importedExpoAnalysis?.declaredSampleCount == legacy.sampleCount)

            let boundaries = capture.attempt.boundaries
            #expect(boundaries.captureStartS == legacy.samples.first?.timestampS)
            #expect(boundaries.captureEndS == legacy.samples.last?.timestampS)
            #expect(boundaries.motionStartS == legacy.releaseTimestampS)
            #expect(boundaries.motionEndS == legacy.catchTimestampS)
            #expect(boundaries.releaseS == nil)
            #expect(boundaries.catchS == nil)
            #expect(boundaries.settledS == nil)

            let firstV2 = try #require(legacy.samples.first)
            let firstV3 = try #require(capture.samplePayload.samples.first)
            #expect(firstV3.sequence == 0)
            #expect(firstV3.timestampS == firstV2.timestampS)
            #expect(abs(firstV3.rotationRateRadS.x - firstV2.rotationRateDps.x * .pi / 180) < 0.000_000_001)
            #expect(firstV3.userAccelerationG == nil)
            #expect(firstV3.gravityG == nil)
            #expect(firstV3.fusedAttitude == nil)
            #expect(firstV3.qualityFlags.contains(.legacyImported))
            #expect(firstV3.qualityFlags.contains(.legacyCombinedAcceleration))
            #expect(firstV3.qualityFlags.contains(.missingUserAcceleration))
            #expect(firstV3.qualityFlags.contains(.missingGravity))
            #expect(firstV3.qualityFlags.contains(.missingFusedAttitude))
            #expect(capture.samplePayload.samples.allSatisfy {
                !$0.qualityFlags.contains(.timestampDuplicate)
                    && !$0.qualityFlags.contains(.timestampNonMonotonic)
                    && !$0.qualityFlags.contains(.timestampGapBefore)
            })

            let originalAccelerationG = Vector3(
                x: firstV2.accelerationIncludingGravity.x / MotionSchemaV3.earthGravityMetersPerSecondSquared,
                y: firstV2.accelerationIncludingGravity.y / MotionSchemaV3.earthGravityMetersPerSecondSquared,
                z: firstV2.accelerationIncludingGravity.z / MotionSchemaV3.earthGravityMetersPerSecondSquared
            )
            #expect(firstV3.accelerationIncludingGravityG == originalAccelerationG)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = try encoder.encode(capture)
            let decoded = try JSONDecoder().decode(MotionCaptureV3.self, from: encoded)
            let reencoded = try encoder.encode(decoded)
            #expect(decoded == capture)
            #expect(reencoded == encoded)
        }
    }

    @Test("migration rejects a raw reference that cannot describe the payload")
    func rejectsMismatchedRawReference() throws {
        let fixture = fixtures[0]
        let legacy = try decodeFixture(named: fixture.file).recordedAttempt
        let invalidReference = RawSampleReferenceV3(
            relativePath: "fixtures/motion/v2/labelled/\(fixture.file)",
            encoding: .expoLabelledCaptureJSON,
            payloadSchemaVersion: 2,
            sampleCount: fixture.sampleCount - 1,
            checksum: fixture.checksum
        )
        let context = ExpoAttemptV2MigrationContext(
            device: migrationDevice,
            gripHand: .right,
            orientation: .unknown,
            referenceFrame: .unknown,
            requestedFrequencyHz: 100,
            versions: migrationVersions,
            rawSamples: invalidReference
        )

        #expect(throws: ExpoAttemptV2MigrationError.rawReferenceSampleCountMismatch(
            reference: fixture.sampleCount - 1,
            payload: fixture.sampleCount
        )) {
            try ExpoAttemptV2Migration.convert(legacy, context: context)
        }
    }

    @Test("legacy migration marks duplicate, non-monotonic and missing timestamp evidence")
    func marksLegacyTimestampQuality() throws {
        let fixture = fixtures[0]
        var legacy = try decodeFixture(named: fixture.file).recordedAttempt
        let base = try #require(legacy.samples.first)
        legacy.samples = [
            MotionSample(
                timestampS: 10,
                accelerationIncludingGravity: base.accelerationIncludingGravity,
                rotationRateDps: base.rotationRateDps
            ),
            MotionSample(
                timestampS: 10,
                accelerationIncludingGravity: base.accelerationIncludingGravity,
                rotationRateDps: base.rotationRateDps
            ),
            MotionSample(
                timestampS: 9.99,
                accelerationIncludingGravity: base.accelerationIncludingGravity,
                rotationRateDps: base.rotationRateDps
            ),
            MotionSample(
                timestampS: 10.03,
                accelerationIncludingGravity: base.accelerationIncludingGravity,
                rotationRateDps: base.rotationRateDps
            ),
        ]
        legacy.sampleCount = legacy.samples.count
        let context = ExpoAttemptV2MigrationContext(
            device: migrationDevice,
            gripHand: .right,
            orientation: .unknown,
            referenceFrame: .unknown,
            requestedFrequencyHz: 100,
            versions: migrationVersions,
            rawSamples: RawSampleReferenceV3(
                relativePath: "fixture.json",
                encoding: .expoLabelledCaptureJSON,
                payloadSchemaVersion: 2,
                sampleCount: legacy.samples.count,
                checksum: "fixture-checksum"
            )
        )

        let migrated = try ExpoAttemptV2Migration.convert(legacy, context: context)
        let samples = migrated.samplePayload.samples

        #expect(samples.map(\.sequence) == [0, 1, 2, 3])
        #expect(samples[1].qualityFlags.contains(.timestampDuplicate))
        #expect(samples[2].qualityFlags.contains(.timestampNonMonotonic))
        #expect(samples[3].qualityFlags.contains(.timestampGapBefore))
    }

    private var migrationDevice: CaptureDeviceMetadataV3 {
        CaptureDeviceMetadataV3(
            modelIdentifier: nil,
            modelName: "iPhone 15 Plus",
            operatingSystemName: "iOS",
            operatingSystemVersion: nil,
            operatingSystemBuild: nil
        )
    }

    private var migrationVersions: ProcessingVersionsV3 {
        ProcessingVersionsV3(
            calibrationProfileID: nil,
            calibrationVersion: nil,
            detectorVersion: "expo-alpha-v2",
            analysisVersion: "expo-alpha-v2",
            scoreVersion: nil
        )
    }

    private func migrationContext(for fixture: FixtureCase) -> ExpoAttemptV2MigrationContext {
        ExpoAttemptV2MigrationContext(
            device: migrationDevice,
            gripHand: .right,
            orientation: .unknown,
            referenceFrame: .unknown,
            requestedFrequencyHz: 100,
            versions: migrationVersions,
            rawSamples: RawSampleReferenceV3(
                relativePath: "fixtures/motion/v2/labelled/\(fixture.file)",
                encoding: .expoLabelledCaptureJSON,
                payloadSchemaVersion: 2,
                sampleCount: fixture.sampleCount,
                checksum: fixture.checksum
            )
        )
    }

    private func decodeFixture(named name: String) throws -> ExpoLabelledCaptureV1 {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryRoot = packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("fixtures/motion/v2/labelled")
            .appendingPathComponent(name)
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(ExpoLabelledCaptureV1.self, from: data)
    }
}
