import KamikazeMotionCore
import SwiftUI

struct PlayView: View {
    @State private var motion = LiveMotionModel()

    private var armed: Bool {
        motion.detection.phase == .armed
            || motion.detection.phase == .airborne
            || motion.detection.phase == .settling
    }

    var body: some View {
        ZStack {
            KineticBackground(accent: armed ? KamikazeTheme.hazard : KamikazeTheme.ion)
            VStack(spacing: 16) {
                HStack {
                    SectionKicker(text: phaseKicker)
                    Spacer()
                    Button("ZERO POSE", systemImage: "scope") {
                        motion.zeroPose()
                    }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .adaptiveGlassButton()
                }

                Spacer(minLength: 8)

                GlassSurface(level: .subtle, cornerRadius: 42) {
                    ZStack {
                        Circle()
                            .fill((armed ? KamikazeTheme.hazard : KamikazeTheme.ion).opacity(0.13))
                            .overlay(Circle().stroke(.white.opacity(0.13)))
                            .padding(10)
                        LivePhoneScene(
                            attitude: motion.relativeAttitude,
                            accent: armed ? KamikazeTheme.hazard : KamikazeTheme.ion
                        )
                    }
                }
                .frame(maxHeight: 430)

                GlassSurface(level: .subtle, cornerRadius: 20) {
                    HStack(spacing: 18) {
                        sensorMetric(title: "MOTION", value: motionLabel)
                        sensorMetric(title: "RATE", value: motion.measuredHz > 0 ? "\(Int(motion.measuredHz.rounded())) HZ" : "— HZ")
                        sensorMetric(title: "GYRO", value: "\(Int(motion.rotationRate.magnitude * 180 / .pi))°/S")
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                }

                VStack(spacing: 6) {
                    Text(phaseTitle)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(-1.2)
                    Text(phaseDetail)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                .multilineTextAlignment(.center)

                Button {
                    withAnimation(.snappy) {
                        armed ? motion.cancelDetection() : motion.armDetection()
                    }
                } label: {
                    Text(primaryButtonTitle)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .adaptiveGlassButton(prominent: true, tint: armed ? KamikazeTheme.hazard : KamikazeTheme.ion)
                .disabled(motion.status != .running)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { motion.start() }
        .onDisappear { motion.stop() }
        .sensoryFeedback(.success, trigger: motion.completedAttemptCount)
        .accessibilityValue(motion.status == .running ? "motion active" : motionLabel)
    }

    private var phaseKicker: String {
        switch motion.detection.phase {
        case .idle: "PLAY / READY"
        case .armed: "SESSION / ARMED"
        case .airborne: "SESSION / MOTION"
        case .settling: "SESSION / LANDING"
        case .complete: "SESSION / LANDED"
        }
    }

    private var phaseTitle: String {
        switch motion.detection.phase {
        case .idle: "READY TO FLIP?"
        case .armed: "THROW WHEN READY"
        case .airborne: "TRICK IN MOTION"
        case .settling: "HOLD THE CATCH"
        case .complete: motion.detection.lastAttempt?.trick ?? "LANDED"
        }
    }

    private var phaseDetail: String {
        switch motion.detection.phase {
        case .idle:
            return motion.status == .running
                ? "Motion capture will run at the device's measured rate."
                : "Motion sensors must be available before starting."
        case .armed:
            return "A quick spin is enough. You do not need a high throw."
        case .airborne:
            return "Rotation captured — catch it and steady the phone."
        case .settling:
            return "Keep it still for a fraction of a second."
        case .complete:
            if let attempt = motion.detection.lastAttempt {
                return "\(Int((attempt.confidence * 100).rounded()))% CONF  ·  \(Int(attempt.airtimeMs.rounded())) MS MOTION  ·  \(attempt.triggerMode == .gyro ? "LOW TRICK" : "AIR")"
            }
            return "Attempt captured."
        }
    }

    private var primaryButtonTitle: String {
        switch motion.detection.phase {
        case .complete: "THROW AGAIN"
        case .armed, .airborne, .settling: "CANCEL SESSION"
        case .idle: "START SESSION"
        }
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
