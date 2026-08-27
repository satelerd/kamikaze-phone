import Observation
import SwiftUI

/// Composer for a display-safe Result projection. A player can publish the
/// card alone, choose an audience, and explicitly opt into each richer upload
/// class. The view owns no persistence or network code.
struct SocialShareComposerView: View {
    let result: SocialResultSnapshot
    let repository: any SocialRepository
    let onPublished: (SocialPost) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var audience: SocialAudience
    @State private var includeReplayVideo = false
    @State private var includeSensorEvidence = false
    @State private var consentAccepted = false
    @State private var consentAcceptedAt: Date?
    @State private var isPublishing = false
    @State private var errorMessage: String?

    init(
        result: SocialResultSnapshot,
        repository: any SocialRepository = MockSocialRepository(),
        initialAudience: SocialAudience = .private,
        onPublished: @escaping (SocialPost) -> Void = { _ in }
    ) {
        self.result = result
        self.repository = repository
        self.onPublished = onPublished
        _audience = State(initialValue: initialAudience)
    }

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.volt)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    PublishedResultCardView(result: result)
                    captionEditor
                    SocialAudiencePicker(selection: $audience)
                    SocialUploadConsentPanel(
                        includeReplayVideo: $includeReplayVideo,
                        includeSensorEvidence: $includeSensorEvidence,
                        consentAccepted: $consentAccepted
                    )
                    publishAction
                    Text("You can unpublish or delete a social record later. Your original local attempt and raw evidence are never changed by sharing.")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: includeReplayVideo) { _, _ in resetConsent() }
        .onChange(of: includeSensorEvidence) { _, _ in resetConsent() }
        .onChange(of: consentAccepted) { _, accepted in
            consentAcceptedAt = accepted ? .now : nil
        }
        .alert("Could not publish", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please review the sharing choices.")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("SHARE\nTHE RESULT")
                    .font(.system(size: 37, weight: .black, design: .rounded))
                    .tracking(-1.5)
                Text("YOU CHOOSE THE AUDIENCE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .adaptiveGlassButton(tint: KamikazeTheme.muted)
                .accessibilityLabel("Close share composer")
        }
    }

    private var captionEditor: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                SocialSectionLabel(title: "CAPTION", detail: "Optional · 280 characters")
                TextField("What did this throw feel like?", text: $caption, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .lineLimit(3...6)
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    Text("Keep the useful detail. Skip the pressure.")
                    Spacer()
                    Text("\(caption.count)/280")
                }
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(caption.count > 280 ? KamikazeTheme.hazard : KamikazeTheme.muted)
            }
            .padding(16)
        }
    }

    private var publishAction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                publish()
            } label: {
                if isPublishing {
                    ProgressView()
                        .tint(KamikazeTheme.pitch)
                        .frame(maxWidth: .infinity, minHeight: 58)
                } else {
                    Label("PUBLISH AS \(audience.title)", systemImage: audience.iconName)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
            }
            .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
            .disabled(!draft.canPublish || isPublishing)
            .accessibilityHint(draft.canPublish ? "Publishes this result to the selected audience." : (draft.validationMessage ?? "Review sharing choices."))

            if let validationMessage = draft.validationMessage {
                Label(validationMessage, systemImage: "info.circle")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.hazard)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var draft: SocialShareDraft {
        SocialShareDraft(
            result: result,
            caption: caption,
            audience: audience,
            includeReplayVideo: includeReplayVideo,
            includeSensorEvidence: includeSensorEvidence,
            uploadConsent: SocialUploadConsent(
                accepted: consentAccepted,
                acceptedAt: consentAcceptedAt
            )
        )
    }

    private func resetConsent() {
        consentAccepted = false
        consentAcceptedAt = nil
    }

    private func publish() {
        guard draft.canPublish, !isPublishing else { return }
        let pendingDraft = draft
        isPublishing = true
        errorMessage = nil
        Task { @MainActor in
            do {
                let post = try await repository.publish(pendingDraft)
                isPublishing = false
                onPublished(post)
                dismiss()
            } catch {
                isPublishing = false
                if let socialError = error as? SocialRepositoryError {
                    errorMessage = socialError.message
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

/// Short alias for integration points that use the product name rather than
/// the feature namespace.
typealias ShareComposerView = SocialShareComposerView
