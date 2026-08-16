import KamikazeMotionCore
import SwiftUI

/// The live pose stage for capture screens (Play and Practice). It exists as
/// its own view so the ~50 Hz attitude publishes invalidate only this body —
/// the host screen re-evaluates on phase changes alone.
struct LiveRunStage: View {
    let run: NativeRunModel
    let accent: Color
    var initialZoom = 0.5

    @Environment(FeedbackCoordinator.self) private var feedback

    var body: some View {
        LivePhoneScene(
            attitude: run.relativeAttitude,
            accent: accent,
            initialZoom: initialZoom,
            onLevel: {
                run.zeroPose()
                feedback.play(.zeroed)
            }
        )
    }
}

/// The numeric capture HUD. The 8 Hz telemetry reads (rate, gyro) live here
/// so the digits refresh without re-evaluating the whole screen. It also owns
/// forwarding gyro energy to the experience field, for the same reason.
struct RunTelemetryHUD: View {
    let run: NativeRunModel
    /// Screen-specific leading metric (Practice shows qualifying reps).
    var leadingTitle: String? = nil
    var leadingValue: String? = nil
    var showsGyro = true

    @Environment(ExperienceCoordinator.self) private var experience

    var body: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
            HStack(spacing: 18) {
                if let leadingTitle, let leadingValue {
                    metric(leadingTitle, leadingValue)
                }
                metric("MOTION", sensorLabel)
                metric("RATE", run.measuredHz > 0 ? "\(Int(run.measuredHz.rounded())) HZ" : "— HZ")
                if showsGyro {
                    metric("GYRO", "\(Int(run.gyroDps.rounded()))°/S")
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        }
        .onChange(of: run.gyroDps) { _, gyroDps in
            experience.reportMotion(gyroDps: gyroDps)
        }
    }

    private var sensorLabel: String {
        if case .failed = run.phase { return "ERROR" }
        return run.measuredHz > 0 ? "LIVE" : "WAITING"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.muted)
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.frost)
        }
        .frame(maxWidth: .infinity)
    }
}
