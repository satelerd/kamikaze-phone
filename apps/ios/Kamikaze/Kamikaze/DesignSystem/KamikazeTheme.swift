import SwiftUI

enum KamikazeTheme {
    static let pitch = Color(red: 0.035, green: 0.04, blue: 0.038)
    static let frost = Color(red: 0.92, green: 0.93, blue: 0.91)
    static let muted = Color(red: 0.60, green: 0.62, blue: 0.59)
    static let ion = Color(red: 0.30, green: 0.40, blue: 1.00)
    static let hazard = Color(red: 1.00, green: 0.38, blue: 0.31)
    static let volt = Color(red: 0.84, green: 1.00, blue: 0.29)
}

/// Field prototypes, selectable from Setup for on-device comparison.
enum FieldStyle: String, CaseIterable, Identifiable {
    /// Metal shader: abstract current-lines with defined edges in a single
    /// accent. GPU per-pixel work — no blurred layers to composite.
    case flux
    /// The original MeshGradient field, single-accent and phase-stable.
    case slipstream

    static let storageKey = "fieldStyle"
    static let `default` = FieldStyle.flux

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flux: "FLUX"
        case .slipstream: "SLIPSTREAM"
        }
    }

    var blurb: String {
        switch self {
        case .flux: "SHADER CURRENTS, GLASS-FRIENDLY"
        case .slipstream: "THE ORIGINAL SOFT FIELD"
        }
    }
}

/// Compatibility wrapper for presentation contexts (onboarding, covers,
/// sheets) that want the field with a fixed accent and no live energy.
struct KineticBackground: View {
    let accent: Color

    var body: some View {
        SlipstreamField(accent: accent)
    }
}

/// The field entry point every screen uses. Renders whichever prototype is
/// selected; replay contexts pass a deterministic time override so the same
/// attempt always produces the same field.
struct SlipstreamField: View {
    let accent: Color
    /// Smoothed 0...1 from `ExperienceCoordinator`. Never raw sensor values.
    var energy: Double = 0
    /// Deterministic seconds for replay-driven fields; nil uses the clock.
    var timeOverride: Double? = nil
    /// Offscreen screens pause their field so stacked tabs cost nothing.
    var paused: Bool = false

    @AppStorage(FieldStyle.storageKey) private var styleRaw = FieldStyle.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var style: FieldStyle {
        FieldStyle(rawValue: styleRaw) ?? .default
    }

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1 / 30,
            paused: reduceMotion || timeOverride != nil || paused
        )) { timeline in
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let time = timeOverride ?? clock

            ZStack {
                KamikazeTheme.pitch
                switch style {
                case .flux:
                    FluxField(accent: accent, energy: energy, time: time, quiet: reduceTransparency)
                case .slipstream:
                    MeshField(accent: accent, energy: energy, time: time, quiet: reduceTransparency)
                }
                LinearGradient(
                    colors: [.black.opacity(0.10), .clear, .black.opacity(0.36)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Shader-driven abstract currents. All the work happens per-pixel on the
/// GPU; the view itself is a single rectangle.
private struct FluxField: View {
    let accent: Color
    let energy: Double
    let time: Double
    let quiet: Bool

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.black)
                .colorEffect(ShaderLibrary.fluxField(
                    .float2(Float(proxy.size.width), Float(proxy.size.height)),
                    // Wall-clock seconds are ~8e8: far beyond float32 phase
                    // precision, which flattens every sin() in the shader.
                    // A modulo keeps the phase exact; one wrap per ~17 min.
                    .float(Float(time.truncatingRemainder(dividingBy: 1_000))),
                    .float(Float(quiet ? 0 : energy)),
                    .color(accent)
                ))
        }
        .opacity(quiet ? 0.35 : 1)
    }
}

/// The original soft MeshGradient, kept as a comparison prototype: single
/// accent only, and energy widens the drift without touching wave phase.
private struct MeshField: View {
    let accent: Color
    let energy: Double
    let time: Double
    let quiet: Bool

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(at: time),
                colors: meshColors,
                smoothsColors: true
            )
            .blur(radius: quiet ? 12 : 34)
            .saturation(1.18)
            .opacity(quiet ? 0.34 : 0.92)

            GeometryReader { proxy in
                let shortEdge = min(proxy.size.width, proxy.size.height)
                Circle()
                    .fill(accent.opacity(quiet ? 0.07 : 0.20 + 0.24 * energy))
                    .frame(width: shortEdge * 0.86, height: shortEdge * 0.86)
                    .blur(radius: 72)
                    .offset(
                        x: proxy.size.width * (0.28 + 0.10 * sin(time * 0.17)),
                        y: proxy.size.height * (0.05 + 0.10 * cos(time * 0.13))
                    )
            }
            .blendMode(.plusLighter)

            Canvas { context, size in
                context.opacity = quiet ? 0.018 : 0.035
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
        }
    }

    private var meshColors: [Color] {
        [
            KamikazeTheme.pitch, KamikazeTheme.pitch, accent.opacity(0.50),
            accent.opacity(0.24), KamikazeTheme.pitch, accent.opacity(0.16),
            KamikazeTheme.pitch, accent.opacity(0.28), KamikazeTheme.pitch,
        ]
    }

    private func meshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        // Energy widens the drift; wave phase stays untouched so the field
        // never jumps when energy changes.
        let drive = Float(1 + energy * 1.4)
        let horizontal = Float(sin(time * 0.19)) * 0.055 * drive
        let vertical = Float(cos(time * 0.14)) * 0.06 * drive
        let counter = Float(sin(time * 0.09 + 1.7)) * 0.035 * drive

        return [
            [0, 0], [0.5 + counter, 0], [1, 0],
            [0, 0.48 + vertical], [0.52 + horizontal, 0.48 - vertical], [1, 0.54 - counter],
            [0, 1], [0.48 - counter, 1], [1, 1],
        ]
    }
}
