import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

/// Development tool, not a test. When `KAMIKAZE_SEED=1`, this writes a
/// synthetic but fully valid capture set into the host app's own attempt
/// storage through the production repositories, so Profile, History pagination
/// and the summary reconciler can be exercised visually in the Simulator
/// without a physical device. Without the environment variable it does nothing.
struct SimulatorSeedTool {
    @MainActor
    @Test func seedSimulatorAttempts() async throws {
        guard ProcessInfo.processInfo.environment["KAMIKAZE_SEED"] == "1" else { return }
        let root = AttemptStorageLocation.applicationRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = FileAttemptRepository(rootDirectory: root)

        var minute = 0
        for round in 0 ..< 4 {
            for profile in SyntheticThrowProfile.allCases {
                let id = "seed-\(profile.rawValue)-\(round)"
                let capture = SyntheticCaptureFactory.make(
                    id: id,
                    recordedAtISO8601: String(format: "2026-08-14T%02d:%02d:00Z", 10 + round, minute % 60),
                    profile: profile
                )
                try await repository.save(capture)
                minute += 7
            }
        }
    }
}

private enum SyntheticThrowProfile: String, CaseIterable {
    case flip
    case reverseFlip = "reverse-flip"
    case backsideShuvit = "bs-360-shuvit"
    case phoneFlip = "phone-flip"
    case weakThrow = "weak-throw"
    case straightAir = "straight-air"
}

private enum SyntheticCaptureFactory {
    static func make(
        id: String,
        recordedAtISO8601: String,
        profile: SyntheticThrowProfile
    ) -> MotionCaptureV3 {
        let hz = 100.0
        let quietLeadS = 0.3
        let motionS = 0.6
        let quietTailS = 0.4
        let totalS = quietLeadS + motionS + quietTailS
        let count = Int(totalS * hz)

        var samples: [MotionSampleV3] = []
        samples.reserveCapacity(count)
        var attitude = Quaternion.identity
        for index in 0 ..< count {
            let t = Double(index) / hz
            let inMotion = t >= quietLeadS && t < quietLeadS + motionS
            let phase = inMotion ? (t - quietLeadS) / motionS : 0
            let rate = inMotion ? rotationRate(profile: profile, phase: phase) : Vector3(x: 0, y: 0, z: 0)
            attitude = QuaternionMath.integrated(
                attitude,
                rotationRateDps: Vector3(
                    x: rate.x * 180 / .pi,
                    y: rate.y * 180 / .pi,
                    z: rate.z * 180 / .pi
                ),
                deltaTimeS: 1 / hz
            )
            let catchSpike = abs(t - (quietLeadS + motionS)) < 0.02
            samples.append(MotionSampleV3(
                sequence: UInt64(index),
                timestampS: t,
                rotationRateRadS: rate,
                userAccelerationG: Vector3(
                    x: 0,
                    y: catchSpike ? 2.5 : (inMotion ? -0.98 : 0),
                    z: 0
                ),
                gravityG: Vector3(x: 0, y: 0, z: 1),
                fusedAttitude: attitude
            ))
        }

        let payload = MotionSamplePayloadV3(attemptID: id, samples: samples)
        let encoded = (try? CapturePersistenceCodec.encode(payload)) ?? Data()
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: recordedAtISO8601,
            captureMode: .auto,
            triggerMode: .gyro,
            boundaries: AttemptBoundariesV3(
                captureStartS: 0,
                captureEndS: totalS,
                motionStartS: quietLeadS,
                motionEndS: quietLeadS + motionS,
                releaseS: quietLeadS,
                catchS: quietLeadS + motionS,
                settledS: quietLeadS + motionS + 0.2
            ),
            environment: CaptureEnvironmentV3(
                device: CaptureDeviceMetadataV3(
                    modelIdentifier: "Simulator",
                    modelName: "Simulator Seed",
                    operatingSystemName: "iOS",
                    operatingSystemVersion: nil,
                    operatingSystemBuild: nil
                ),
                gripHand: .right,
                orientation: .portrait,
                referenceFrame: .xArbitraryZVertical,
                requestedFrequencyHz: hz,
                measuredFrequencyHz: hz
            ),
            versions: ProcessingVersionsV3(
                calibrationProfileID: nil,
                calibrationVersion: nil,
                detectorVersion: "simulator-seed-v1",
                analysisVersion: "simulator-seed-v1",
                scoreVersion: nil
            ),
            rawSamples: RawSampleReferenceV3(
                relativePath: "raw/\(id).samples.v3.json",
                encoding: .json,
                payloadSchemaVersion: MotionSchemaV3.version,
                sampleCount: samples.count,
                checksum: CapturePersistenceCodec.sha256(encoded)
            ),
            importedExpoAnalysis: nil
        )
        return MotionCaptureV3(attempt: attempt, samplePayload: payload)
    }

    /// Rates in rad/s over a normalized 0...1 motion phase, loosely shaped
    /// after the 2026-08-13 physical medians so the v0.2 matcher sees a
    /// plausible mix of recognized, review and unknown outcomes.
    private static func rotationRate(profile: SyntheticThrowProfile, phase: Double) -> Vector3 {
        let wobble = sin(phase * 2 * .pi)
        switch profile {
        case .flip:
            return Vector3(x: 1.2 * wobble, y: 11.1, z: -0.9 * wobble)
        case .reverseFlip:
            return Vector3(x: 1.3 * wobble, y: -10.6, z: 0.8 * wobble)
        case .backsideShuvit:
            return Vector3(x: 2.6 * wobble, y: -0.4, z: 10.5)
        case .phoneFlip:
            return Vector3(x: 10.9 * wobble, y: 14.1, z: -7.1 * wobble)
        case .weakThrow:
            return Vector3(x: 0.9 * wobble, y: 3.4, z: 0.7)
        case .straightAir:
            return Vector3(x: 0.2 * wobble, y: 0.3, z: 0.1)
        }
    }
}
