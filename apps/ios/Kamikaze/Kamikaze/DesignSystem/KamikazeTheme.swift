import SwiftUI

enum KamikazeTheme {
    static let pitch = Color(red: 0.035, green: 0.04, blue: 0.038)
    static let frost = Color(red: 0.92, green: 0.93, blue: 0.91)
    static let muted = Color(red: 0.60, green: 0.62, blue: 0.59)
    static let ion = Color(red: 0.30, green: 0.40, blue: 1.00)
    static let hazard = Color(red: 1.00, green: 0.38, blue: 0.31)
    static let volt = Color(red: 0.84, green: 1.00, blue: 0.29)
}

/// Compatibility wrapper for presentation contexts (onboarding, covers,
/// sheets) that want the field with a fixed accent and no live energy.
struct KineticBackground: View {
    let accent: Color

    var body: some View {
        SlipstreamField(accent: accent)
    }
}

/// Slipstream Field v2: one MeshGradient-based field whose drift, speed and
/// halo respond to smoothed motion energy. In replay contexts a deterministic
/// time override derived from the playhead replaces the wall clock, so the
/// same attempt always produces the same field.
struct SlipstreamField: View {
    let accent: Color
    /// Smoothed 0...1 from `ExperienceCoordinator`. Never raw sensor values.
    var energy: Double = 0
    /// Deterministic seconds for replay-driven fields; nil uses the clock.
    var timeOverride: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || timeOverride != nil)) { timeline in
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let time = timeOverride ?? clock

            ZStack {
                KamikazeTheme.pitch

                MeshGradient(
                    width: 3,
                    height: 3,
                    points: meshPoints(at: time),
                    colors: meshColors,
                    smoothsColors: true
                )
                .blur(radius: reduceTransparency ? 12 : 34)
                .saturation(1.18)
                .opacity(reduceTransparency ? 0.34 : 0.92)

                GeometryReader { proxy in
                    let shortEdge = min(proxy.size.width, proxy.size.height)

                    Circle()
                        .fill(accent.opacity(reduceTransparency ? 0.07 : 0.20 + 0.24 * energy))
                        .frame(width: shortEdge * 0.86, height: shortEdge * 0.86)
                        .blur(radius: 72)
                        .offset(
                            x: proxy.size.width * (0.28 + 0.10 * sin(time * 0.17)),
                            y: proxy.size.height * (0.05 + 0.10 * cos(time * 0.13))
                        )

                    Circle()
                        .fill(KamikazeTheme.hazard.opacity(reduceTransparency ? 0.04 : 0.12))
                        .frame(width: shortEdge * 0.68, height: shortEdge * 0.68)
                        .blur(radius: 82)
                        .offset(
                            x: -proxy.size.width * (0.12 + 0.08 * cos(time * 0.11)),
                            y: proxy.size.height * (0.56 + 0.08 * sin(time * 0.15))
                        )
                }
                .blendMode(.plusLighter)

                Canvas { context, size in
                    context.opacity = reduceTransparency ? 0.018 : 0.035
                    var y: CGFloat = 0
                    while y < size.height {
                        context.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)),
                            with: .color(.white)
                        )
                        y += 7
                    }
                }
                .blendMode(.overlay)

                LinearGradient(
                    colors: [.black.opacity(0.08), .clear, .black.opacity(0.38)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }

    private var meshColors: [Color] {
        [
            KamikazeTheme.pitch, KamikazeTheme.pitch, accent.opacity(0.50),
            accent.opacity(0.24), KamikazeTheme.pitch, KamikazeTheme.hazard.opacity(0.20),
            KamikazeTheme.pitch, accent.opacity(0.28), KamikazeTheme.pitch,
        ]
    }

    private func meshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        // Rotation energy opens the field: faster drift and wider shear while
        // the phone is actually moving, quiet when it is not.
        let drive = Float(1 + energy * 1.6)
        let speed = 1 + energy * 2.2
        let horizontal = Float(sin(time * 0.19 * speed)) * 0.055 * drive
        let vertical = Float(cos(time * 0.14 * speed)) * 0.06 * drive
        let counter = Float(sin(time * 0.09 * speed + 1.7)) * 0.035 * drive

        return [
            [0, 0], [0.5 + counter, 0], [1, 0],
            [0, 0.48 + vertical], [0.52 + horizontal, 0.48 - vertical], [1, 0.54 - counter],
            [0, 1], [0.48 - counter, 1], [1, 1],
        ]
    }
}
