import SwiftUI

struct GlassSurface<Content: View>: View {
    let interactive: Bool
    @ViewBuilder let content: Content

    init(interactive: Bool = false, @ViewBuilder content: () -> Content) {
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: 24)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.12), lineWidth: 0.7)
                }
        }
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

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(tint)
            } else {
                content.buttonStyle(.glass).tint(tint)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).tint(tint)
        } else {
            content.buttonStyle(.bordered).tint(tint)
        }
    }
}

extension View {
    func adaptiveGlassButton(prominent: Bool = false, tint: Color = KamikazeTheme.ion) -> some View {
        modifier(AdaptiveGlassButtonModifier(prominent: prominent, tint: tint))
    }
}
