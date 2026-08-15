import SwiftUI

/// Beta bench: every experiment and comparison toggle lives here while the
/// game is in beta, so trying a prototype never requires a rebuild — and
/// removing this tab later removes the whole bench at once.
struct BetaView: View {
    @Environment(ExperienceCoordinator.self) private var experience
    @Environment(FeedbackCoordinator.self) private var feedback
    @AppStorage(FieldStyle.storageKey) private var fieldStyleRaw = FieldStyle.default.rawValue
    @AppStorage(BetaFlags.verticalArc) private var verticalArc = false
    @AppStorage(BetaFlags.fieldDisabled) private var fieldDisabled = false

    var body: some View {
        @Bindable var feedback = feedback
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionKicker(text: "BETA / EXPERIMENT BENCH")
                    Text("TRY IT.\nBREAK IT. TELL US.")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .tracking(-1.6)
                    Text("Everything here is a prototype switch. Nothing changes your saved evidence.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)

                    GlassSurface {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FIELD STYLE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.muted)
                                .padding(.top, 14)
                            ForEach(FieldStyle.allCases) { style in
                                Button {
                                    fieldStyleRaw = style.rawValue
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(style.displayName)
                                                .font(.system(size: 13, weight: .black, design: .rounded))
                                            Text(style.blurb)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundStyle(KamikazeTheme.muted)
                                        }
                                        Spacer()
                                        Image(systemName: fieldStyleRaw == style.rawValue
                                            ? "largecircle.fill.circle"
                                            : "circle")
                                            .foregroundStyle(fieldStyleRaw == style.rawValue
                                                ? KamikazeTheme.volt
                                                : KamikazeTheme.muted)
                                    }
                                    .frame(minHeight: 52)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }

                    GlassSurface {
                        VStack(spacing: 0) {
                            toggleRow(
                                "VERTICAL ARC (ESTIMATED)",
                                detail: "Replay adds a ballistic up/down arc from motion duration. Estimated, not measured.",
                                isOn: $verticalArc
                            )
                            Divider()
                            toggleRow(
                                "SOUND — V0 KIT",
                                detail: "Synthesized kinetic foley draft. Silent switch is respected.",
                                isOn: $feedback.soundEnabled
                            )
                            Divider()
                            toggleRow(
                                "HAPTICS",
                                detail: "Never fires while evidence is being captured.",
                                isOn: $feedback.hapticsEnabled
                            )
                            Divider()
                            toggleRow(
                                "DISABLE FIELD",
                                detail: "Kill switch to isolate background cost.",
                                isOn: $fieldDisabled
                            )
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: fieldDisabled) { _, disabled in
                        experience.fieldDisabled = disabled
                    }

                    Button("PREVIEW FEEDBACK CUES") {
                        feedback.play(.landed(scoreBand: 2))
                    }
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .adaptiveGlassButton(tint: KamikazeTheme.volt)
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func toggleRow(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
            }
        }
        .tint(KamikazeTheme.volt)
        .frame(minHeight: 58)
    }
}

/// AppStorage keys for beta experiments.
enum BetaFlags {
    static let verticalArc = "betaVerticalArc"
    static let fieldDisabled = "debugDisableField"
}
