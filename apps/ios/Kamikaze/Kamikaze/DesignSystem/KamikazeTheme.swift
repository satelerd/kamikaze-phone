import SwiftUI

enum KamikazeTheme {
    static let pitch = Color(red: 0.035, green: 0.04, blue: 0.038)
    static let frost = Color(red: 0.92, green: 0.93, blue: 0.91)
    static let muted = Color(red: 0.60, green: 0.62, blue: 0.59)
    static let ion = Color(red: 0.30, green: 0.40, blue: 1.00)
    static let hazard = Color(red: 1.00, green: 0.38, blue: 0.31)
    static let volt = Color(red: 0.84, green: 1.00, blue: 0.29)
}

struct KineticBackground: View {
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

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
                        .fill(accent.opacity(reduceTransparency ? 0.07 : 0.20))
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
        let horizontal = Float(sin(time * 0.19)) * 0.055
        let vertical = Float(cos(time * 0.14)) * 0.06
        let counter = Float(sin(time * 0.09 + 1.7)) * 0.035

        return [
            [0, 0], [0.5 + counter, 0], [1, 0],
            [0, 0.48 + vertical], [0.52 + horizontal, 0.48 - vertical], [1, 0.54 - counter],
            [0, 1], [0.48 - counter, 1], [1, 1],
        ]
    }
}
