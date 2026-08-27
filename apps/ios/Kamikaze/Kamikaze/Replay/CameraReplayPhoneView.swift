import AVFoundation
import KamikazeMotionCore
import RealityKit
import SwiftUI

nonisolated enum CameraReplayTiming {
    static func videoTime(
        replayTimeS: Double,
        replayDurationS: Double,
        motionCaptureStartS: Double,
        artifact: CameraRunRecordingArtifact
    ) -> Double {
        let offset: Double
        if let sourceStart = artifact.sourceStartTimestampS {
            offset = motionCaptureStartS - sourceStart
        } else {
            offset = max(0, (artifact.durationS - replayDurationS) / 2)
        }
        return min(artifact.durationS, max(0, offset + replayTimeS))
    }

    /// Builds an editor timeline from the entire recorded source. The phone
    /// holds its initial pose during the introduction, executes measured
    /// motion at the original host-clock offset, then holds the catch while
    /// the camera keeps recording the reaction.
    static func fullTakeFrames(
        motionFrames: [ReplayFrame],
        motionCaptureStartS: Double,
        artifact: CameraRunRecordingArtifact
    ) -> [ReplayFrame] {
        let normalized = ReplayBuilder.normalized(motionFrames)
        guard let first = normalized.first, let last = normalized.last else { return [] }

        let motionDurationS = max(0, last.timestampMs / 1_000)
        let offsetS: Double
        if let sourceStart = artifact.sourceStartTimestampS {
            offsetS = min(artifact.durationS, max(0, motionCaptureStartS - sourceStart))
        } else {
            offsetS = max(0, (artifact.durationS - motionDurationS) / 2)
        }
        let offsetMs = offsetS * 1_000
        let durationMs = max(artifact.durationS * 1_000, offsetMs + last.timestampMs)

        var output = normalized.map { frame in
            ReplayFrame(
                timestampMs: offsetMs + frame.timestampMs,
                progress: 0,
                quaternion: frame.quaternion,
                accelG: frame.accelG,
                gyroDps: frame.gyroDps
            )
        }
        if offsetMs > 0 {
            output.insert(ReplayFrame(
                timestampMs: 0,
                progress: 0,
                quaternion: first.quaternion,
                accelG: first.accelG,
                gyroDps: 0
            ), at: 0)
        }
        if let final = output.last, final.timestampMs < durationMs {
            output.append(ReplayFrame(
                timestampMs: durationMs,
                progress: 1,
                quaternion: last.quaternion,
                accelG: last.accelG,
                gyroDps: 0
            ))
        }
        guard durationMs > 0 else { return output }
        return output.map { frame in
            var updated = frame
            updated.progress = min(1, max(0, frame.timestampMs / durationMs))
            return updated
        }
    }
}

/// Reuses the exact same ReplayPhoneView transport while projecting the saved
/// front-camera clip onto the virtual phone. Camera and motion are aligned by
/// their original monotonic timestamps, not by an authored percentage.
struct CameraReplayPhoneView: View {
    @Bindable var controller: ReplayController
    let accent: Color
    let targetFrames: [ReplayFrame]?
    let arcWindow: FreefallWindow?
    let take: PlayCameraTake?
    let motionCaptureStartS: Double
    /// Editor timelines already use camera-source time, so their offset is 0.
    /// Result timelines leave this nil and align from monotonic timestamps.
    let videoTimelineOffsetS: Double?

    @State private var player: AVPlayer?
    @State private var material: VideoMaterial?

    init(
        controller: ReplayController,
        accent: Color,
        targetFrames: [ReplayFrame]? = nil,
        arcWindow: FreefallWindow? = nil,
        take: PlayCameraTake?,
        motionCaptureStartS: Double,
        videoTimelineOffsetS: Double? = nil
    ) {
        self.controller = controller
        self.accent = accent
        self.targetFrames = targetFrames
        self.arcWindow = arcWindow
        self.take = take
        self.motionCaptureStartS = motionCaptureStartS
        self.videoTimelineOffsetS = videoTimelineOffsetS
    }

    var body: some View {
        ReplayPhoneView(
            controller: controller,
            accent: accent,
            targetFrames: targetFrames,
            arcWindow: arcWindow,
            screenVideoMaterial: material
        )
        .overlay(alignment: .topTrailing) {
            if material != nil {
                Text("CAMERA SYNC")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .task(id: take?.id) { await preparePlayer() }
        .onChange(of: controller.state) { _, _ in synchronize(forceSeek: true) }
        .onChange(of: controller.speed) { _, _ in synchronize(forceSeek: true) }
        .onChange(of: controller.playheadMs) { _, _ in
            synchronize(forceSeek: controller.state != .playing)
        }
        .onDisappear { player?.pause() }
    }

    private func preparePlayer() async {
        player?.pause()
        guard let artifact = take?.front else {
            player = nil
            material = nil
            return
        }
        let newPlayer = AVPlayer(url: artifact.url)
        newPlayer.actionAtItemEnd = .pause
        // Prime the local file before exposing its VideoMaterial. Use an
        // exact seek, never AVPlayer.preroll: iOS 26 aborts inside
        // `prerollAtRate` for this freshly-finalized camera asset (confirmed
        // by physical-device crash report A0B4B23A-67CA-4370-8833-B8BE909C1A32).
        let initialTimeS = videoTimelineOffsetS.map { max(0, $0) }
            ?? CameraReplayTiming.videoTime(
                replayTimeS: controller.playheadMs / 1_000,
                replayDurationS: controller.durationMs / 1_000,
                motionCaptureStartS: motionCaptureStartS,
                artifact: artifact
            )
        await newPlayer.seek(
            to: CMTime(seconds: initialTimeS, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        player = newPlayer
        material = VideoMaterial(avPlayer: newPlayer)
        synchronize(forceSeek: true)
    }

    private func synchronize(forceSeek: Bool) {
        guard let player, let artifact = take?.front else { return }
        let targetS = videoTimelineOffsetS.map {
            min(artifact.durationS, max(0, $0 + controller.playheadMs / 1_000))
        } ?? CameraReplayTiming.videoTime(
            replayTimeS: controller.playheadMs / 1_000,
            replayDurationS: controller.durationMs / 1_000,
            motionCaptureStartS: motionCaptureStartS,
            artifact: artifact
        )
        let currentS = player.currentTime().seconds
        let drift = currentS.isFinite ? abs(currentS - targetS) : .infinity
        if forceSeek || drift > 0.18 {
            player.seek(
                to: CMTime(seconds: targetS, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        if controller.state == .playing {
            player.playImmediately(atRate: Float(controller.speed.rawValue))
        } else {
            player.pause()
        }
    }

}
