import KamikazeMotionCore
import SwiftUI

struct PlayView: View {
    @State private var armed = false
    @State private var motion = LiveMotionModel()

    var body: some View {
        ZStack {
            KineticBackground(accent: armed ? KamikazeTheme.hazard : KamikazeTheme.ion)
            VStack(spacing: 16) {
                HStack {
                    SectionKicker(text: armed ? "SESSION / ARMED" : "PLAY / READY")
                    Spacer()
                    Button("ZERO POSE", systemImage: "scope") {
                        motion.zeroPose()
                    }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .adaptiveGlassButton()
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill((armed ? KamikazeTheme.hazard : KamikazeTheme.ion).opacity(0.15))
                        .overlay(Circle().stroke(.white.opacity(0.12)))
                    LivePhoneScene(
                        attitude: motion.relativeAttitude,
                        accent: armed ? KamikazeTheme.hazard : KamikazeTheme.ion
                    )
                }
                .frame(maxHeight: 430)

                HStack(spacing: 18) {
                    sensorMetric(title: "MOTION", value: motionLabel)
                    sensorMetric(title: "RATE", value: motion.measuredHz > 0 ? "\(Int(motion.measuredHz.rounded())) HZ" : "— HZ")
                    sensorMetric(title: "GYRO", value: "\(Int(motion.rotationRate.magnitude * 180 / .pi))°/S")
                }

                VStack(spacing: 6) {
                    Text(armed ? "THROW WHEN READY" : "READY TO FLIP?")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(-1.2)
                    Text(armed ? "Automatic detection will close the attempt." : "Motion capture will run at the device's measured rate.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                .multilineTextAlignment(.center)

                Button(armed ? "CANCEL SESSION" : "START SESSION") {
                    withAnimation(.snappy) { armed.toggle() }
                }
                .font(.system(size: 18, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 72)
                .adaptiveGlassButton(prominent: true, tint: armed ? KamikazeTheme.hazard : KamikazeTheme.ion)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { motion.start() }
        .onDisappear { motion.stop() }
        .accessibilityValue(motion.status == .running ? "motion active" : motionLabel)
    }

    private var motionLabel: String {
        switch motion.status {
        case .idle: "IDLE"
        case .running: "LIVE"
        case .unavailable: "SIMULATOR"
        case .failed: "ERROR"
        }
    }

    private func sensorMetric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(KamikazeTheme.frost)
        }
        .frame(maxWidth: .infinity)
    }
}
