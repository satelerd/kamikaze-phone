import KamikazeMotionCore
import SwiftUI

struct PlayView: View {
    @State private var armed = false
    private let initialPose = Quaternion.identity

    var body: some View {
        ZStack {
            KineticBackground(accent: armed ? KamikazeTheme.hazard : KamikazeTheme.ion)
            VStack(spacing: 16) {
                HStack {
                    SectionKicker(text: armed ? "SESSION / ARMED" : "PLAY / READY")
                    Spacer()
                    Button("ZERO POSE", systemImage: "scope") { }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .adaptiveGlassButton()
                }

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill((armed ? KamikazeTheme.hazard : KamikazeTheme.ion).opacity(0.15))
                        .overlay(Circle().stroke(.white.opacity(0.12)))
                    RoundedRectangle(cornerRadius: 26)
                        .fill(.black.gradient)
                        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.28)))
                        .frame(width: 132, height: 270)
                        .rotation3DEffect(.degrees(armed ? -16 : 8), axis: (x: 1, y: 1, z: 0))
                        .shadow(color: (armed ? KamikazeTheme.hazard : KamikazeTheme.ion).opacity(0.55), radius: 38)
                        .accessibilityLabel("Live phone pose")
                }
                .frame(maxHeight: 430)

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
        .accessibilityValue(initialPose.w == 1 ? "zero pose" : "pose active")
    }
}
