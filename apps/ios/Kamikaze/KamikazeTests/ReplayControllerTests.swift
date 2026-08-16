import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct ReplayControllerTests {
    @MainActor
    @Test func manualClockAdvancesAtSelectedSpeed() {
        let controller = ReplayController(frames: frames(), clockMode: .manual)
        // Study speed (0.5×) is the default; tricks resolve too fast for 1×.
        #expect(controller.speed == .half)
        controller.play()
        controller.advance(by: 100)
        #expect(controller.playheadMs == 50)

        controller.setSpeed(.normal)
        controller.advance(by: 100)
        #expect(controller.playheadMs == 150)
    }

    @MainActor
    @Test func pausePreventsDeterministicClockAdvance() {
        let controller = ReplayController(frames: frames(), clockMode: .manual)
        controller.play()
        controller.advance(by: 100)
        controller.pause()
        controller.advance(by: 400)
        #expect(controller.playheadMs == 50)
        #expect(controller.state == .paused)
    }

    @MainActor
    @Test func seekPausesAndSamplesRequestedPosition() {
        let controller = ReplayController(frames: frames(), clockMode: .manual)
        controller.play()
        controller.seek(toProgress: 0.5)
        #expect(controller.playheadMs == 500)
        #expect(controller.state == .paused)
        #expect(controller.sampledFrame.timestampMs == 500)
    }

    @MainActor
    @Test func playbackEndsAtFinalFrame() {
        let controller = ReplayController(frames: frames(), clockMode: .manual)
        controller.setSpeed(.quarter)
        controller.play()
        controller.advance(by: 4_100)
        #expect(controller.playheadMs == 1_000)
        #expect(controller.state == .ended)
    }

    @MainActor
    @Test func zeroPoseDoesNotResetCamera() {
        let controller = ReplayController(frames: frames(), clockMode: .manual)
        controller.orbit(deltaX: 50, deltaY: -10)
        let camera = controller.camera
        controller.seek(toProgress: 0.5)
        controller.zeroPose()
        #expect(controller.camera == camera)
        #expect(controller.displayFrame.quaternion == .identity)
        controller.resetCamera()
        #expect(controller.camera == .spectator)
    }

    private func frames() -> [ReplayFrame] {
        [
            ReplayFrame(timestampMs: 0, progress: 0, quaternion: .identity, accelG: 1, gyroDps: 0),
            ReplayFrame(timestampMs: 1_000, progress: 1, quaternion: Quaternion(w: 0, x: 0, y: 1, z: 0), accelG: 1, gyroDps: 0),
        ]
    }
}
