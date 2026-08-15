import KamikazeMotionCore
import SwiftUI

/// The Setup screen (player-facing name prototype; internal Locker name stays
/// until the label is validated). One interactive phone built by the shared
/// factory; every choice previews live across the whole app through
/// `AppearanceStore`, and `EQUIP` commits it.
struct LockerView: View {
    private enum Category: String, CaseIterable, Identifiable {
        case model = "MODEL"
        case body = "BODY"
        case edge = "EDGE"
        case screen = "SCREEN"

        var id: String { rawValue }
    }

    @Environment(AppearanceStore.self) private var store
    @State private var category = Category.body
    @State private var progressModel = PracticeModel()

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionKicker(text: "SETUP / BUILD YOUR PHONE")
                    Text("YOUR PHONE.\nYOUR BOARD.")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(-1.8)

                    GlassSurface(role: .stage, cornerRadius: 36) {
                        LivePhoneScene(
                            attitude: .identity,
                            accent: KamikazeTheme.ion,
                            initialYaw: -2.62,
                            initialPitch: 0.16
                        )
                        .frame(minHeight: 340)
                    }

                    equipBar

                    HStack(spacing: 8) {
                        ForEach(Category.allCases) { candidate in
                            Button {
                                category = candidate
                            } label: {
                                Text(candidate.rawValue)
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundStyle(category == candidate ? Color.black : KamikazeTheme.frost)
                                    .padding(.horizontal, 13)
                                    .frame(minHeight: 34)
                                    .background(
                                        category == candidate ? KamikazeTheme.volt : Color.white.opacity(0.08),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    optionRail
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Task { await progressModel.refresh() } }
        .onDisappear { store.discardPreview() }
    }

    @ViewBuilder
    private var equipBar: some View {
        if store.hasPendingPreview {
            HStack(spacing: 10) {
                Button("EQUIP") {
                    store.equipPreview()
                }
                .font(.system(size: 15, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 56)
                .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)

                Button("DISCARD") {
                    store.discardPreview()
                }
                .font(.system(size: 13, weight: .black, design: .rounded))
                .frame(minWidth: 110, minHeight: 56)
                .adaptiveGlassButton(tint: KamikazeTheme.hazard)
            }
        } else {
            Text("EQUIPPED  ·  APPLIES IN PLAY, PRACTICE AND REPLAY")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
        }
    }

    @ViewBuilder
    private var optionRail: some View {
        switch category {
        case .model:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PhoneFormFactor.allCases) { factor in
                        optionCard(
                            title: factor.displayName,
                            color: nil,
                            selected: store.effective.formFactor == factor,
                            lockedLabel: nil
                        ) {
                            store.previewChange { $0.formFactor = factor }
                        }
                    }
                }
            }
        case .body:
            cosmeticRail(
                options: CosmeticCatalog.bodies,
                selectedID: store.effective.bodyID
            ) { option in
                store.previewChange { $0.bodyID = option.id }
            }
        case .edge:
            cosmeticRail(
                options: CosmeticCatalog.edges,
                selectedID: store.effective.edgeID
            ) { option in
                store.previewChange { $0.edgeID = option.id }
            }
        case .screen:
            cosmeticRail(
                options: CosmeticCatalog.screens,
                selectedID: store.effective.screenID
            ) { option in
                store.previewChange { $0.screenID = option.id }
            }
        }
    }

    private func cosmeticRail(
        options: [CosmeticOption],
        selectedID: String,
        select: @escaping (CosmeticOption) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(options) { option in
                    let unlocked = CosmeticCatalog.isUnlocked(option, progress: progressModel.progress)
                    optionCard(
                        title: option.displayName,
                        color: option.color.color,
                        selected: selectedID == option.id,
                        lockedLabel: unlocked ? nil : CosmeticCatalog.unlockLabel(for: option)
                    ) {
                        select(option)
                    }
                }
            }
        }
    }

    /// Locked choices always show the concrete unlock condition, never only a
    /// padlock.
    private func optionCard(
        title: String,
        color: Color?,
        selected: Bool,
        lockedLabel: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlassSurface(role: .interactiveCard, cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    if let color {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(color.gradient)
                            .frame(width: 92, height: 54)
                            .opacity(lockedLabel == nil ? 1 : 0.35)
                    } else {
                        Image(systemName: "iphone.gen3")
                            .font(.system(size: 34))
                            .frame(width: 92, height: 54)
                            .foregroundStyle(KamikazeTheme.frost)
                    }
                    Text(title)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                    if let lockedLabel {
                        Label(lockedLabel, systemImage: "lock.fill")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.hazard)
                    } else {
                        Text(selected ? "SELECTED" : "AVAILABLE")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(selected ? KamikazeTheme.volt : KamikazeTheme.muted)
                    }
                }
                .padding(12)
            }
        }
        .buttonStyle(.plain)
        .disabled(lockedLabel != nil)
    }
}
