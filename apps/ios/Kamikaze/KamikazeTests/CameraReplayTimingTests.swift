import Foundation
import Testing
@testable import Kamikaze

struct CameraReplayTimingTests {
    @Test func monotonicSourceTimestampAlignsVideoToMotionCapture() {
        let artifact = CameraRunRecordingArtifact(
            url: URL(fileURLWithPath: "/tmp/front.mp4"),
            durationS: 5,
            frameCount: 150,
            sourceStartTimestampS: 100,
            sourceEndTimestampS: 105
        )

        let time = CameraReplayTiming.videoTime(
            replayTimeS: 0.45,
            replayDurationS: 1,
            motionCaptureStartS: 101.2,
            artifact: artifact
        )
        #expect(abs(time - 1.65) < 1e-9)
    }

    @Test func videoTimeIsClampedToRecordedSource() {
        let artifact = CameraRunRecordingArtifact(
            url: URL(fileURLWithPath: "/tmp/front.mp4"),
            durationS: 2,
            frameCount: 60,
            sourceStartTimestampS: 100
        )

        #expect(CameraReplayTiming.videoTime(
            replayTimeS: 4,
            replayDurationS: 4,
            motionCaptureStartS: 101,
            artifact: artifact
        ) == 2)
        #expect(CameraReplayTiming.videoTime(
            replayTimeS: 0,
            replayDurationS: 1,
            motionCaptureStartS: 99,
            artifact: artifact
        ) == 0)
    }

    @Test func artifactsSavedBeforeCameraV2StillDecode() throws {
        struct LegacyArtifact: Encodable {
            let url: URL
            let durationS: Double
            let frameCount: Int
        }
        let data = try JSONEncoder().encode(LegacyArtifact(
            url: URL(fileURLWithPath: "/tmp/legacy.mp4"),
            durationS: 3,
            frameCount: 90
        ))
        let decoded = try JSONDecoder().decode(CameraRunRecordingArtifact.self, from: data)

        #expect(decoded.sourceStartTimestampS == nil)
        #expect(decoded.sourceEndTimestampS == nil)
        #expect(decoded.frameCount == 90)
    }
}
