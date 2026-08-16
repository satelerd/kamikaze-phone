import KamikazeMotionCore
import PhotosUI
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
    @Environment(FeedbackCoordinator.self) private var feedback
    @State private var category = Category.body
    @State private var progressModel = PracticeModel()
    /// The stage mirrors the phone in your hand, exactly like Play.
    @State private var preview = AttitudePreviewModel()
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("YOUR PHONE.\nYOUR BOARD.")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(-1.8)

                    GlassSurface(role: .stage, cornerRadius: 36) {
                        LivePhoneScene(
                            attitude: preview.relativeAttitude,
                            accent: KamikazeTheme.ion,
                            cameraPose: cameraPose,
                            onLevel: {
                                preview.zeroPose()
                                feedback.play(.zeroed)
                            }
                        )
                        .frame(minHeight: 340)
                    }

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
        .onAppear {
            preview.start()
            Task { await progressModel.refresh() }
        }
        .onDisappear {
            preview.stop()
        }
    }

    /// Every selection applies and saves immediately — no EQUIP step.
    private func apply(_ transform: (inout PhoneAppearance) -> Void) {
        store.applyChange(transform)
        feedback.play(.cosmeticUnlocked)
    }

    /// The camera frames whatever the active section edits: the back for
    /// BODY, the rim for EDGE, the front for SCREEN, the showcase 3/4 for
    /// MODEL. The phone itself keeps mirroring the player's hand.
    private var cameraPose: StageCameraPose {
        switch category {
        case .model: StageCameraPose(yaw: -2.62, pitch: 0.16, zoom: 0.70)
        case .body: StageCameraPose(yaw: .pi, pitch: 0.10, zoom: 0.54)
        case .edge: StageCameraPose(yaw: .pi / 2, pitch: 0.04, zoom: 0.44)
        case .screen: StageCameraPose(yaw: 0, pitch: 0.02, zoom: 0.54)
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
                            apply { $0.formFactor = factor }
                        }
                    }
                }
            }
        case .body:
            cosmeticRail(
                options: CosmeticCatalog.bodies,
                selectedID: store.effective.bodyID
            ) { option in
                apply { $0.bodyID = option.id }
            }
        case .edge:
            cosmeticRail(
                options: CosmeticCatalog.edges,
                selectedID: store.effective.edgeID
            ) { option in
                apply { $0.edgeID = option.id }
            }
        case .screen:
            VStack(alignment: .leading, spacing: 12) {
                cosmeticRail(
                    options: CosmeticCatalog.screens,
                    selectedID: store.effective.screenID
                ) { option in
                    apply { $0.screenID = option.id }
                }
                if store.effective.usesCustomPhotoScreen {
                    photoPickerRow
                }
            }
        }
    }

    /// PHOTO's companion control: pick the image the virtual screen shows.
    /// A screenshot of the real home screen is the intended use.
    private var photoPickerRow: some View {
        HStack(spacing: 12) {
            if let image = CustomScreenStore.shared.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    CustomScreenStore.shared.hasImage ? "CHANGE PHOTO" : "CHOOSE PHOTO",
                    systemImage: "photo"
                )
                .font(.system(size: 12, weight: .black, design: .rounded))
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
            .adaptiveGlassButton()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    CustomScreenStore.shared.setImageData(data)
                    feedback.play(.cosmeticUnlocked)
                }
                photoItem = nil
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
