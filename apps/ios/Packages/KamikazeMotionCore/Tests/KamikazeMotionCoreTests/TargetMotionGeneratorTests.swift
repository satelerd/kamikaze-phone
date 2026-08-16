import Foundation
import Testing
@testable import KamikazeMotionCore

@Suite("Target motion generator")
struct TargetMotionGeneratorTests {
    private func definition(
        _ target: Vector3,
        durationMs: Double = 700
    ) -> TrickDefinition {
        TrickDefinition(
            id: .flip,
            displayName: "TEST",
            family: .flip,
            targetRotationDegrees: target,
            referenceDurationMs: durationMs
        )
    }

    @Test("integrates exactly to the signed target rotation")
    func integratesToTarget() {
        // A half rotation is unambiguous in quaternion space.
        let half = definition(Vector3(x: 0, y: 0, z: 180))
        let frames = TargetMotionGenerator.frames(for: half, frameRateHz: 120)
        let final = frames.last!.quaternion

        let expected = QuaternionMath.integrated(
            .identity,
            rotationRateDps: Vector3(x: 0, y: 0, z: 180),
            deltaTimeS: 1
        )
        let dot = abs(final.w * expected.w + final.x * expected.x
            + final.y * expected.y + final.z * expected.z)
        #expect(dot > 0.9995, "final pose deviates from the 180° target")
    }

    @Test("is deterministic and monotonic with a still settle tail")
    func deterministicAndWellFormed() {
        let trick = definition(Vector3(x: 0, y: 370, z: 0))
        let first = TargetMotionGenerator.frames(for: trick)
        let second = TargetMotionGenerator.frames(for: trick)
        #expect(first == second)

        #expect(first.first?.quaternion == .identity)
        #expect(first.last?.progress == 1)
        #expect(zip(first, first.dropFirst()).allSatisfy { $0.timestampMs < $1.timestampMs })

        // The tail holds the catch pose, motionless.
        let tail = first.suffix(5)
        #expect(tail.allSatisfy { $0.gyroDps == 0 })
        #expect(Set(tail.map(\.quaternion.w)).count == 1)
    }

    @Test("eases: still at release and catch, fastest at the peak")
    func envelopeShape() {
        let trick = definition(Vector3(x: 0, y: 360, z: 0), durationMs: 600)
        let frames = TargetMotionGenerator.frames(for: trick, frameRateHz: 100, settleTailS: 0)
        let peak = frames.map(\.gyroDps).max() ?? 0
        #expect(frames.first?.gyroDps == 0)
        #expect((frames.last?.gyroDps ?? 1) < peak * 0.05)
        let midIndex = frames.count / 2
        #expect(frames[midIndex].gyroDps > peak * 0.95)
    }
}
