import Foundation
import KamikazeMotionCore
import Observation

/// A single replay state machine shared by Result, saved attempts and Practice.
/// It owns time and camera/reference state, but deliberately knows nothing
/// about scores, detector labels or a particular navigation destination.
@MainActor
@Observable
final class ReplayController {
    enum PlaybackState: Equatable {
        case paused
        case playing
        case ended
    }

    enum PlaybackSpeed: Double, CaseIterable, Identifiable {
        case quarter = 0.25
        case half = 0.5
        case normal = 1

        var id: Double { rawValue }
        var label: String { rawValue == 1 ? "1×" : "\(rawValue)×" }
    }

    enum ClockMode: Sendable {
        /// Uses a ContinuousClock task at approximately display cadence.
        case continuous
        /// A deterministic host advances via `advance(by:)`; used by tests,
        /// previews and any future display-link owner.
        case manual
    }

    struct Camera: Equatable, Sendable {
        var azimuth: Double
        var elevation: Double
        var distance: Double

        static let spectator = Camera(azimuth: -0.48, elevation: 0.22, distance: 0.48)
    }

    private let frames: [ReplayFrame]
    private let clockMode: ClockMode
    @ObservationIgnored private var playbackTask: Task<Void, Never>?

    private(set) var state: PlaybackState = .paused
    private(set) var playheadMs: Double = 0
    /// Half speed by default: a real trick resolves in a few hundred ms, so
    /// 1× replays read as a blink. 0.5× is the study speed.
    var speed: PlaybackSpeed = .half
    var camera: Camera = .spectator
    private(set) var poseBaseline: Quaternion?

    init(
        payload: MotionSamplePayloadV3,
        boundaries: AttemptBoundariesV3,
        clockMode: ClockMode = .continuous
    ) {
        self.frames = ReplayBuilder.normalized(
            ReplayBuilder.buildFrames(payload: payload, boundaries: boundaries)
        )
        self.clockMode = clockMode
    }

    init(frames: [ReplayFrame], clockMode: ClockMode = .continuous) {
        self.frames = ReplayBuilder.normalized(frames)
        self.clockMode = clockMode
    }

    deinit {
        playbackTask?.cancel()
    }

    var hasReplay: Bool { !frames.isEmpty }
    var durationMs: Double { frames.last?.timestampMs ?? 0 }
    var progress: Double {
        guard durationMs > 0 else { return 0 }
        return min(1, max(0, playheadMs / durationMs))
    }

    var sampledFrame: ReplayFrame {
        ReplayBuilder.sample(frames, at: playheadMs)
    }

    /// The visual pose only. Zero Pose never changes the selected camera.
    var displayFrame: ReplayFrame {
        let frame = sampledFrame
        guard let poseBaseline else { return frame }
        let relative = QuaternionMath.relative(from: poseBaseline, to: frame.quaternion)
        return ReplayFrame(
            timestampMs: frame.timestampMs,
            progress: frame.progress,
            quaternion: relative,
            accelG: frame.accelG,
            gyroDps: frame.gyroDps
        )
    }

    func play() {
        guard hasReplay else { return }
        if progress >= 1 { seek(toProgress: 0) }
        state = .playing
        startContinuousDriverIfNeeded()
    }

    func pause() {
        state = progress >= 1 ? .ended : .paused
        playbackTask?.cancel()
        playbackTask = nil
    }

    func togglePlayback() {
        state == .playing ? pause() : play()
    }

    func seek(toProgress progress: Double) {
        playheadMs = durationMs * min(1, max(0, progress))
        state = self.progress >= 1 && durationMs > 0 ? .ended : .paused
        playbackTask?.cancel()
        playbackTask = nil
    }

    /// Injected deterministic clock input. It is public so a future
    /// CADisplayLink can drive this controller without replacing its state.
    func advance(by elapsedMs: Double) {
        guard state == .playing, elapsedMs > 0, durationMs > 0 else { return }
        playheadMs = min(durationMs, playheadMs + elapsedMs * speed.rawValue)
        if playheadMs >= durationMs {
            state = .ended
            playbackTask?.cancel()
            playbackTask = nil
        }
    }

    func setSpeed(_ speed: PlaybackSpeed) {
        self.speed = speed
    }

    func orbit(deltaX: Double, deltaY: Double) {
        camera.azimuth -= deltaX * 0.008
        camera.elevation = min(.pi * 0.46, max(-.pi * 0.46, camera.elevation + deltaY * 0.008))
    }

    func zoom(magnification: Double) {
        guard magnification.isFinite, magnification > 0 else { return }
        camera.distance = min(1.2, max(0.38, camera.distance / magnification))
    }

    /// Restores only the spectator camera; it never changes Zero Pose.
    func resetCamera() {
        camera = .spectator
    }

    /// Sets the visible orientation reference at the current playhead. It does
    /// not alter replay samples, timing or the camera.
    func zeroPose() {
        poseBaseline = sampledFrame.quaternion
    }

    func clearZeroPose() {
        poseBaseline = nil
    }

    private func startContinuousDriverIfNeeded() {
        guard clockMode == .continuous, playbackTask == nil else { return }
        playbackTask = Task { @MainActor [weak self] in
            let clock = ContinuousClock()
            var previous = clock.now
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: .milliseconds(16))
                } catch {
                    return
                }
                guard let self, self.state == .playing else { return }
                let now = clock.now
                let elapsed = now - previous
                previous = now
                self.advance(by: elapsed.milliseconds)
            }
        }
    }
}

private extension Duration {
    var milliseconds: Double {
        let components = components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
