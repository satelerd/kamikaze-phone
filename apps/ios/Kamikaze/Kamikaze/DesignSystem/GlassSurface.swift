import SwiftUI

enum GlassSurfaceLevel {
    case subtle
    case regular
    case elevated

    var strokeOpacity: Double {
        switch self {
        case .subtle: 0.10
        case .regular: 0.15
        case .elevated: 0.22
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .subtle: 0.08
        case .regular: 0.16
        case .elevated: 0.25
        }
    }
}

struct GlassSurface<Content: View>: View {
    let interactive: Bool
    let level: GlassSurfaceLevel
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        interactive: Bool = false,
        level: GlassSurfaceLevel = .regular,
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.interactive = interactive
        self.level = level
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            content
                .background(
                    KamikazeTheme.pitch.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay { glassBorder }
        } else if #available(iOS 26, *) {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
                .overlay { glassBorder }
                .shadow(color: .black.opacity(level.shadowOpacity), radius: 24, y: 14)
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay { glassBorder }
                .shadow(color: .black.opacity(level.shadowOpacity), radius: 24, y: 14)
        }
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(level.strokeOpacity + 0.08),
                        .white.opacity(level.strokeOpacity * 0.25),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
            .allowsHitTesting(false)
    }
}

struct SectionKicker: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.3)
            .foregroundStyle(KamikazeTheme.volt)
    }
}

private struct AdaptiveGlassButtonModifier: ViewModifier {
    let prominent: Bool
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .buttonStyle(.borderedProminent)
                .tint(prominent ? tint : KamikazeTheme.pitch)
        } else if #available(iOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(tint)
            } else {
                content.buttonStyle(.glass).tint(tint)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent).tint(tint)
            } else {
                content.buttonStyle(.bordered).tint(tint)
            }
        }
    }
}

extension View {
    func adaptiveGlassButton(prominent: Bool = false, tint: Color = KamikazeTheme.ion) -> some View {
        modifier(AdaptiveGlassButtonModifier(prominent: prominent, tint: tint))
    }
}
