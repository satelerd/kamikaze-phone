import SwiftUI

enum KamikazeTheme {
    static let pitch = Color(red: 0.035, green: 0.04, blue: 0.038)
    static let frost = Color(red: 0.92, green: 0.93, blue: 0.91)
    static let muted = Color(red: 0.60, green: 0.62, blue: 0.59)
    static let ion = Color(red: 0.30, green: 0.40, blue: 1.00)
    static let hazard = Color(red: 1.00, green: 0.38, blue: 0.31)
    static let volt = Color(red: 0.84, green: 1.00, blue: 0.29)
}

/// Field prototypes, selectable from Setup so styles can be compared on the
/// physical device. Shared rules for every style: only the current semantic
/// accent is used (no fixed second color bleeding into results), energy
/// modulates amplitude and intensity — never a wave's phase — and accent
/// changes cross-fade instead of snapping.
enum FieldStyle: String, CaseIterable, Identifiable {
    /// Defined diagonal light beams. Hard-edged shapes give Liquid Glass
    /// something real to refract.
    case beams
    /// A low glow and a sharp horizon line.
    case horizon
    /// One defined ring of light behind the stage.
    case halo
    /// The original MeshGradient field, single-accent and phase-stable.
    case slipstream

    static let storageKey = "fieldStyle"
    static let `default` = FieldStyle.beams

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .beams: "BEAMS"
        case .horizon: "HORIZON"
        case .halo: "HALO"
        case .slipstream: "SLIPSTREAM"
        }
    }

    var blurb: String {
        switch self {
        case .beams: "DEFINED LIGHT, GLASS-FRIENDLY"
        case .horizon: "LOW GLOW + SHARP LINE"
        case .halo: "ONE QUIET RING"
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

    @AppStorage(FieldStyle.storageKey) private var styleRaw = FieldStyle.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var style: FieldStyle {
        FieldStyle(rawValue: styleRaw) ?? .default
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || timeOverride != nil)) { timeline in
            let clock = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let time = timeOverride ?? clock

            ZStack {
                KamikazeTheme.pitch
                switch style {
                case .beams:
                    BeamsField(accent: accent, energy: energy, time: time, quiet: reduceTransparency)
                case .horizon:
                    HorizonField(accent: accent, energy: energy, time: time, quiet: reduceTransparency)
                case .halo:
                    HaloField(accent: accent, energy: energy, time: time, quiet: reduceTransparency)
                case .slipstream:
                    MeshField(accent: accent, energy: energy, time: time, quiet: reduceTransparency)
                }
                LinearGradient(
                    colors: [.black.opacity(0.10), .clear, .black.opacity(0.36)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Semantic accent changes (ready → motion → landed) cross-fade.
            .animation(.easeInOut(duration: 0.6), value: accent)
        }
        .ignoresSafeArea()
    }
}

/// Three defined diagonal beams drifting slowly. Amplitude and opacity follow
/// energy; phase never jumps.
private struct BeamsField: View {
    let accent: Color
    let energy: Double
    let time: Double
    let quiet: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let baseOpacity = quiet ? 0.05 : 0.13 + 0.20 * energy

            ZStack {
                beam(width: width * 0.30, height: height * 1.7)
                    .opacity(baseOpacity)
                    .offset(x: width * (-0.22 + 0.05 * sin(time * 0.11)), y: 0)
                beam(width: width * 0.16, height: height * 1.7)
                    .opacity(baseOpacity * 0.8)
                    .offset(x: width * (0.16 + 0.06 * sin(time * 0.08 + 1.9)), y: 0)
                beam(width: width * 0.09, height: height * 1.7)
                    .opacity(baseOpacity * 0.65)
                    .offset(x: width * (0.42 + 0.04 * sin(time * 0.14 + 3.4)), y: 0)
            }
            .rotationEffect(.degrees(-24))
            .position(x: width / 2, y: height / 2)
        }
    }

    private func beam(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width / 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.9), accent.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: height)
            .blur(radius: 1.5)
    }
}

/// A low radial glow under the stage plus one sharp horizon line.
private struct HorizonField: View {
    let accent: Color
    let energy: Double
    let time: Double
    let quiet: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let horizonY = height * 0.62
            let glow = quiet ? 0.06 : 0.16 + 0.22 * energy

            ZStack {
                RadialGradient(
                    colors: [accent.opacity(glow), accent.opacity(glow * 0.35), .clear],
                    center: UnitPoint(x: 0.5, y: horizonY / height),
                    startRadius: 10,
                    endRadius: width * (0.62 + 0.05 * sin(time * 0.10))
                )
                Rectangle()
                    .fill(accent.opacity(quiet ? 0.25 : 0.55 + 0.30 * energy))
                    .frame(height: 1.5)
                    .position(x: width / 2, y: horizonY)
                Rectangle()
                    .fill(accent.opacity(quiet ? 0.08 : 0.16))
                    .frame(height: 0.75)
                    .position(x: width / 2, y: horizonY + 10 + 2 * sin(time * 0.22))
            }
        }
    }
}

/// One defined ring behind the stage. The quietest prototype.
private struct HaloField: View {
    let accent: Color
    let energy: Double
    let time: Double
    let quiet: Bool

    var body: some View {
        GeometryReader { proxy in
            let shortEdge = min(proxy.size.width, proxy.size.height)
            let diameter = shortEdge * (0.78 + 0.05 * energy + 0.015 * sin(time * 0.16))

            Circle()
                .stroke(
                    accent.opacity(quiet ? 0.15 : 0.32 + 0.30 * energy),
                    lineWidth: 10 + 8 * energy
                )
                .frame(width: diameter, height: diameter)
                .blur(radius: 5)
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.40)
        }
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
