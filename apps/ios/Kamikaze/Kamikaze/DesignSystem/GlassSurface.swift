import SwiftUI

/// The functional job a glass surface performs. Roles decide material
/// behavior; individual views never re-style glass with their own borders or
/// shadows, so the native material stays untouched on iOS 26.
enum GlassRole {
    /// Larger reading surface: cards, lists, settings. Quiet regular glass.
    case contentPanel
    /// Sparse live state and evidence readouts (rates, phases, tapes).
    case instrumentHUD
    /// A tappable/selectable card that should respond to touch, such as a
    /// cosmetic choice or a record that opens its replay.
    case interactiveCard
    /// Backdrop framing a 3D stage. The quietest role: the phone is the hero.
    case stage
    /// A cluster of playback tools: play, scrub, speed. One surface for the
    /// whole group, never one capsule per control.
    case transport

    var isInteractive: Bool {
        self == .interactiveCard
    }
}

/// Beta experiment: which Liquid Glass material every `GlassSurface` uses.
/// CLEAR is the default per player feedback ("more transparent"); the picker
/// in BETA exists to compare against REGULAR and a tinted draft. Buttons keep
/// their own style — this only governs panels, HUDs and cards.
enum GlassVariant: String, CaseIterable, Identifiable {
    case clear
    case regular
    case tinted

    static let storageKey = "betaGlassVariant"
    static let `default` = GlassVariant.clear

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: "CLEAR"
        case .regular: "REGULAR"
        case .tinted: "TINTED"
        }
    }

    var blurb: String {
        switch self {
        case .clear: "MOST TRANSPARENT — FIELD SHOWS THROUGH"
        case .regular: "SYSTEM DEFAULT FROST"
        case .tinted: "REGULAR WITH AN ION WASH"
        }
    }

    @available(iOS 26, *)
    func glass(interactive: Bool) -> Glass {
        let base: Glass = switch self {
        case .clear: .clear
        case .regular: .regular
        case .tinted: .regular.tint(KamikazeTheme.ion.opacity(0.30))
        }
        return interactive ? base.interactive() : base
    }
}

/// One glass implementation with exactly one fallback boundary:
/// - iOS 26: real Liquid Glass, no decorative border, no custom shadow.
/// - iOS 18–25: ultra-thin material with a hairline border for separation.
/// - Reduce Transparency (any OS): opaque pitch surface with a border.
/// Feature views choose a role; they do not branch on OS version.
struct GlassSurface<Content: View>: View {
    let role: GlassRole
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(GlassVariant.storageKey) private var glassVariantRaw = GlassVariant.default.rawValue

    init(
        role: GlassRole = .contentPanel,
        cornerRadius: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
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
                .overlay { fallbackBorder }
        } else if #available(iOS 26, *) {
            let variant = GlassVariant(rawValue: glassVariantRaw) ?? .default
            content
                .glassEffect(
                    variant.glass(interactive: role.isInteractive),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay { fallbackBorder }
        }
    }

    /// Separation for the non-glass paths only. Native Liquid Glass provides
    /// its own edge treatment and must not be painted over.
    private var fallbackBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(.white.opacity(0.14), lineWidth: 0.75)
            .allowsHitTesting(false)
    }
}

/// Groups related glass so neighboring shapes can blend and morph on iOS 26.
/// On earlier systems the group renders unchanged. Give persistent controls a
/// stable identity with `.kamikazeGlassID(_:in:)` so state changes morph
/// instead of replacing the surface.
struct GlassCluster<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// Stable glass identity inside a `GlassCluster`; a no-op before iOS 26.
    @ViewBuilder
    func kamikazeGlassID(_ id: some Hashable & Sendable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
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
            // Prominent CTAs are tinted GLASS, not a solid capsule: the field
            // behind must stay visible through every button.
            if prominent {
                content.buttonStyle(.glass).tint(tint)
            } else {
                content.buttonStyle(.glass).tint(tint.opacity(0.85))
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
