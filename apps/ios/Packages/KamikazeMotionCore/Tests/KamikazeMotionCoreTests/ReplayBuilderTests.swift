import Foundation
import Testing
@testable import KamikazeMotionCore

@Suite("Expo v2 motion parity")
struct ReplayBuilderTests {
    @Test("relative quaternion removes the zero-pose baseline")
    func relativeQuaternionRemovesBaseline() {
        let halfTurn = Quaternion(w: 0, x: 0, y: 1, z: 0)
        let relative = QuaternionMath.relative(from: halfTurn, to: halfTurn)

        #expect(abs(relative.w - 1) < 0.000_001)
        #expect(abs(relative.x) < 0.000_001)
        #expect(abs(relative.y) < 0.000_001)
        #expect(abs(relative.z) < 0.000_001)
    }

    @Test("decodes both labelled iPhone fixtures and reconstructs replay")
    func labelledFixtures() throws {
        for item in [
            ("iphone15plus-right-phone-flip-001.json", "PHONE FLIP", 202),
            ("iphone15plus-right-reverse-phone-flip-001.json", "REVERSE PHONE FLIP", 217),
        ] {
            let capture = try decodeFixture(named: item.0)
            let frames = ReplayBuilder.normalized(ReplayBuilder.buildFrames(for: capture.recordedAttempt))

            #expect(capture.schema == "kpf-labelled-capture-v1")
            #expect(capture.expectedTrick == item.1)
            #expect(capture.recordedAttempt.schemaVersion == 2)
            #expect(capture.recordedAttempt.source == .sensor)
            #expect(capture.recordedAttempt.sampleCount == item.2)
            #expect(capture.recordedAttempt.samples.count == item.2)
            #expect(frames.count == item.2)
            #expect(frames.first?.timestampMs == 0)
            #expect(frames.last?.progress == 1)
            #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.timestampMs <= $1.timestampMs })
        }
    }

    @Test("samples irregular replay frames by elapsed time")
    func timeSampling() {
        let frames = [
            ReplayFrame(timestampMs: 0, progress: 0, quaternion: .identity, accelG: 1, gyroDps: 0),
            ReplayFrame(timestampMs: 100, progress: 0.5, quaternion: Quaternion(w: 0, x: 1, y: 0, z: 0), accelG: 0, gyroDps: 360),
            ReplayFrame(timestampMs: 400, progress: 1, quaternion: .identity, accelG: 1, gyroDps: 0),
        ]

        let sampled = ReplayBuilder.sample(frames, at: 50)

        #expect(abs(sampled.progress - 0.25) < 0.0001)
        #expect(abs(abs(sampled.quaternion.x) - sqrt(0.5)) < 0.0001)
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
