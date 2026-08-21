import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct MediaExportPlanTests {
    @Test
    func replayPlanSamplesMeasuredSourceTimeAtOutputCadence() throws {
        let frames = [
            ReplayFrame(timestampMs: 0, progress: 0, quaternion: .identity, accelG: 1, gyroDps: 0),
            ReplayFrame(timestampMs: 500, progress: 0.5, quaternion: .identity, accelG: 0.4, gyroDps: 300),
            ReplayFrame(timestampMs: 1_000, progress: 1, quaternion: .identity, accelG: 1, gyroDps: 0)
        ]
        let plan = try ReplayVideoExportPlan(
            frames: frames,
            trim: CameraRunTrim(startS: 0.2, endS: 0.8),
            canvas: .vertical,
            frameRate: 10
        )

        #expect(abs(plan.durationS - 0.6) < 1e-9)
        #expect(plan.frameCount == 6)
        #expect(plan.sourceFrameTimesMs == [200, 300, 400, 500, 600, 700])
        #expect(plan.canvas == .vertical)
    }

    @Test
    func cameraRunExportPlanKeepsCompositionExplicit() throws {
        let url = URL(filePath: "/tmp/camera-run.mp4")
        let timeline = CameraRunTimeline(originUptimeS: 10)
        let clip = try CameraRunDraftClip(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            source: .camera,
            originalDurationS: 3,
            cameraVideoURL: url,
            timeline: timeline
        )
        let plan = try CameraRunExportPlan(clip: clip, frameRate: 30)

        #expect(plan.renderPath == .existingCameraVideo)
        #expect(plan.durationS == 3)
        #expect(plan.frameCount == 90)
        #expect(plan.source == .camera)
    }

    @Test
    func invalidExportInputsFailDeterministically() throws {
        let frame = ReplayFrame(timestampMs: 100, progress: 1, quaternion: .identity, accelG: 1, gyroDps: 0)
        do {
            _ = try ReplayVideoExportPlan(
                frames: [frame],
                trim: CameraRunTrim(startS: 0, endS: 0),
                frameRate: 30
            )
            Issue.record("An empty trim was accepted.")
        } catch let error as ReplayVideoExportError {
            #expect(error == .invalidTrim)
        }

        let timeline = CameraRunTimeline(originUptimeS: 0)
        let clip = try CameraRunDraftClip(
            source: .composite,
            originalDurationS: 2,
            cameraVideoURL: URL(filePath: "/tmp/rear.mp4"),
            timeline: timeline
        )
        let compositePlan = try CameraRunExportPlan(clip: clip)
        #expect(compositePlan.renderPath == .compositionRequired)
    }
}
