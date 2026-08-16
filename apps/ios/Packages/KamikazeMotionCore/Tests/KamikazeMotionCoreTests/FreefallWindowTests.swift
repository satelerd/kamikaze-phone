import Foundation
import Testing
@testable import KamikazeMotionCore

@Suite("Measured free-fall window")
struct FreefallWindowTests {
    private func frame(atMs t: Double, accelG: Double) -> ReplayFrame {
        ReplayFrame(timestampMs: t, progress: 0, quaternion: .identity, accelG: accelG, gyroDps: 0)
    }

    /// hold (1 g) → throw spike → free fall (~0.15 g) → catch spike → hold.
    private func throwFrames(freefallMs: Double) -> [ReplayFrame] {
        var frames: [ReplayFrame] = []
        for t in stride(from: 0.0, to: 200, by: 10) { frames.append(frame(atMs: t, accelG: 1.0)) }
        for t in stride(from: 200.0, to: 260, by: 10) { frames.append(frame(atMs: t, accelG: 2.4)) }
        for t in stride(from: 260.0, through: 260 + freefallMs, by: 10) {
            frames.append(frame(atMs: t, accelG: 0.15))
        }
        let catchStart = 270 + freefallMs
        for t in stride(from: catchStart, to: catchStart + 60, by: 10) { frames.append(frame(atMs: t, accelG: 3.1)) }
        for t in stride(from: catchStart + 60, to: catchStart + 260, by: 10) { frames.append(frame(atMs: t, accelG: 1.0)) }
        return frames
    }

    @Test("detects the airborne span of a throw")
    func detectsThrow() throws {
        let window = try #require(ReplayBuilder.freefallWindow(in: throwFrames(freefallMs: 400)))
        #expect(abs(window.startMs - 260) < 1)
        #expect(abs(window.endMs - 660) < 1)
        // 0.4 s of hang time is a ~20 cm ballistic peak (g·T²/8).
        #expect(abs(window.peakHeightM - 0.196) < 0.005)
    }

    @Test("a spin in the hand has no free fall")
    func handSpinHasNone() {
        let frames = (0 ..< 100).map { frame(atMs: Double($0) * 10, accelG: 0.95 + Double($0 % 3) * 0.1) }
        #expect(ReplayBuilder.freefallWindow(in: frames) == nil)
    }

    @Test("a short bobble below the minimum duration is rejected")
    func shortBobbleRejected() {
        #expect(ReplayBuilder.freefallWindow(in: throwFrames(freefallMs: 60)) == nil)
    }

    @Test("the longest low-acceleration run wins over earlier noise dips")
    func longestRunWins() throws {
        var frames = (0 ..< 5).map { frame(atMs: Double($0) * 10, accelG: 0.3) }
        frames.append(contentsOf: throwFrames(freefallMs: 300).map {
            self.frame(atMs: $0.timestampMs + 100, accelG: $0.accelG)
        })
        let window = try #require(ReplayBuilder.freefallWindow(in: frames))
        #expect(window.startMs > 300)
        #expect(abs(window.durationS - 0.3) < 0.01)
    }

    @Test("ballistic height is zero outside the window and peaks mid-flight")
    func ballisticHeight() {
        let window = FreefallWindow(startMs: 100, endMs: 500)
        #expect(window.heightM(at: 50) == 0)
        #expect(window.heightM(at: 600) == 0)
        #expect(abs(window.heightM(at: 300) - window.peakHeightM) < 0.000_1)
        #expect(window.heightM(at: 150) > 0)
        #expect(window.heightM(at: 150) < window.peakHeightM)
    }
}
