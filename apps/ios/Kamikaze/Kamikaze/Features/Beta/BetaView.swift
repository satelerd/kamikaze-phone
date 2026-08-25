import SwiftUI

/// Beta bench: every experiment and comparison toggle lives here while the
/// game is in beta, so trying a prototype never requires a rebuild — and
/// removing this tab later removes the whole bench at once.
struct BetaView: View {
    @Environment(ExperienceCoordinator.self) private var experience
    @Environment(FeedbackCoordinator.self) private var feedback
    @AppStorage(FieldStyle.storageKey) private var fieldStyleRaw = FieldStyle.default.rawValue
    @AppStorage(GlassVariant.storageKey) private var glassVariantRaw = GlassVariant.default.rawValue
    @AppStorage(BetaFlags.resultMetric) private var resultMetricRaw = ResultMetricMode.default.rawValue
    @AppStorage(BetaFlags.verticalArc) private var verticalArc = true
    @AppStorage(BetaFlags.airBonus) private var airBonus = true
    @AppStorage(BetaFlags.followMode) private var followMode = false
    @AppStorage(BetaFlags.classicMode) private var classicMode = false
    @AppStorage(BetaFlags.fieldDisabled) private var fieldDisabled = false

    var body: some View {
        @Bindable var feedback = feedback
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("TRY IT.\nBREAK IT. TELL US.")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .tracking(-1.6)
                    Text("Everything here is a prototype switch. Nothing changes your saved evidence.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)

                    GlassSurface {
                        optionList(title: "FIELD STYLE", options: FieldStyle.allCases,
                                   selectedRaw: $fieldStyleRaw)
                    }

                    GlassSurface {
                        optionList(title: "LIQUID GLASS", options: GlassVariant.allCases,
                                   selectedRaw: $glassVariantRaw)
                    }

                    GlassSurface {
                        optionList(title: "RESULT METRIC", options: ResultMetricMode.allCases,
                                   selectedRaw: $resultMetricRaw)
                    }

                    GlassSurface {
                        VStack(spacing: 0) {
                            toggleRow(
                                "SHOW ESTIMATED AIR ARC",
                                detail: "Uses measured air time and ballistic physics. Vertical position is not directly measured by the IMU.",
                                isOn: $verticalArc
                            )
                            Divider()
                            toggleRow(
                                "AIR BONUS (EXPERIMENTAL)",
                                detail: "Adds 0–10 result points from estimated peak height. Raw evidence and base score stay unchanged.",
                                isOn: $airBonus
                            )
                            Divider()
                            toggleRow(
                                "FOLLOW MODE IN PLAY",
                                detail: "Random labelled prompts with automatic capture and quick landed/missed review.",
                                isOn: $followMode
                            )
                            Divider()
                            toggleRow(
                                "CLASSIC MODE IN PLAY",
                                detail: "Original Kamikaze: score only measured air time and estimated peak height.",
                                isOn: $classicMode
                            )
                            Divider()
                            toggleRow(
                                "SOUND",
                                detail: "Two minimal cues only: detection success and miss.",
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

                    HStack(spacing: 10) {
                        Button("HEAR SUCCESS") {
                            feedback.play(.landed(scoreBand: 2))
                            feedback.playDetectionSound(success: true)
                        }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .adaptiveGlassButton(tint: KamikazeTheme.volt)

                        Button("HEAR MISS") {
                            feedback.play(.missed)
                            feedback.playDetectionSound(success: false)
                        }
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .adaptiveGlassButton(tint: KamikazeTheme.hazard)
                    }

                    NavigationLink {
                        WorkshopView()
                    } label: {
                        Label("SENSOR WORKSHOP", systemImage: "waveform.badge.magnifyingglass")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .adaptiveGlassButton(tint: KamikazeTheme.ion)

                    Text("CLOUD + SOCIAL LAB")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                        .padding(.top, 8)

                    NavigationLink {
                        ClerkAccountSurface(clerk: KamikazeIdentityConfiguration.clerk)
                    } label: {
                        Label("ACCOUNT", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .adaptiveGlassButton(tint: KamikazeTheme.ion)

                    NavigationLink {
                        CameraRunPrototypeView()
                    } label: {
                        Label("CAMERA RUNS + EDITOR", systemImage: "video.badge.ellipsis")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .adaptiveGlassButton(tint: KamikazeTheme.hazard)

                    NavigationLink {
                        SocialFeedView()
                    } label: {
                        Label("SOCIAL FEED", systemImage: "person.2.wave.2")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .adaptiveGlassButton(tint: KamikazeTheme.volt)

                    NavigationLink {
                        CommunityTrickExchangeView()
                    } label: {
                        Label("TRICK EXCHANGE", systemImage: "arrow.triangle.2.circlepath.circle")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .adaptiveGlassButton(tint: KamikazeTheme.hazard)

                    NavigationLink {
                        SocialShareComposerView(result: .demo)
                    } label: {
                        Label("SHARE COMPOSER DEMO", systemImage: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .adaptiveGlassButton(tint: KamikazeTheme.ion)

                    Text("iPhone 3D models by MajdyModels (CC BY 4.0) and LagzDesign (CC BY), via Sketchfab.")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                        .padding(.top, 8)
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func optionList(
        title: String,
        options: [some FieldOption],
        selectedRaw: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
                .padding(.top, 14)
            ForEach(options, id: \.id) { option in
                Button {
                    selectedRaw.wrappedValue = option.rawValue
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(option.displayName)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                            Text(option.blurb)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.muted)
                        }
                        Spacer()
                        Image(systemName: selectedRaw.wrappedValue == option.rawValue
                            ? "largecircle.fill.circle"
                            : "circle")
                            .foregroundStyle(selectedRaw.wrappedValue == option.rawValue
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

/// Shared shape of the pickable prototype enums (field styles, glass
/// variants), so BETA renders them with one list implementation.
@MainActor
protocol FieldOption: Identifiable, RawRepresentable where RawValue == String {
    var displayName: String { get }
    var blurb: String { get }
}

extension FieldStyle: @MainActor FieldOption {}
extension GlassVariant: @MainActor FieldOption {}
extension ResultMetricMode: @MainActor FieldOption {}

/// Presentation experiment only. Raw evidence, classifications and both
/// underlying metrics remain stored, so switching modes is reversible.
nonisolated enum ResultMetricMode: String, CaseIterable, Identifiable {
    case gameScore
    case legacyFit
    case compare

    static let `default`: Self = .compare
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gameScore: "GAME SCORE V1"
        case .legacyFit: "FIT (LEGACY)"
        case .compare: "COMPARE BOTH"
        }
    }

    var blurb: String {
        switch self {
        case .gameScore: "Completion, purity, catch stability and flow."
        case .legacyFit: "Only similarity to the selected trick definition."
        case .compare: "Score is primary; FIT remains visible beside it."
        }
    }
}

/// AppStorage keys for beta experiments.
enum BetaFlags {
    static let verticalArc = "betaEstimatedVerticalArcV2"
    static let airBonus = "betaEstimatedAirBonusV1"
    static let followMode = "betaFollowPlayModeV1"
    static let classicMode = "betaClassicPlayModeV1"
    static let fieldDisabled = "debugDisableField"
    static let resultMetric = "betaResultMetric"
}
