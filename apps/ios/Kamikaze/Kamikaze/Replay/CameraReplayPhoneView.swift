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

    @State private var player: AVPlayer?
    @State private var material: VideoMaterial?

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
        .task(id: take?.id) { preparePlayer() }
        .onChange(of: controller.state) { _, _ in synchronize(forceSeek: true) }
        .onChange(of: controller.speed) { _, _ in synchronize(forceSeek: true) }
        .onChange(of: controller.playheadMs) { _, _ in
            synchronize(forceSeek: controller.state != .playing)
        }
        .onDisappear { player?.pause() }
    }

    private func preparePlayer() {
        player?.pause()
        guard let artifact = take?.front else {
            player = nil
            material = nil
            return
        }
        let newPlayer = AVPlayer(url: artifact.url)
        newPlayer.actionAtItemEnd = .pause
        player = newPlayer
        material = VideoMaterial(avPlayer: newPlayer)
        synchronize(forceSeek: true)
    }

    private func synchronize(forceSeek: Bool) {
        guard let player, let artifact = take?.front else { return }
        let targetS = CameraReplayTiming.videoTime(
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
