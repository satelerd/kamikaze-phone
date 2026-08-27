import Observation
import SwiftUI

@MainActor
@Observable
final class CommunityTrickExchangeModel {
    enum Section: String, CaseIterable, Identifiable {
        case field
        case mine
        case review

        var id: String { rawValue }

        var title: String {
            switch self {
            case .field: "FIELD"
            case .mine: "MINE"
            case .review: "REVIEW"
            }
        }
    }

    let creatorID: String
    var section: Section = .field
    private(set) var snapshot: CommunityTrickSnapshot = .empty
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let workflow: CommunityTrickWorkflow

    init(
        repository: any CommunityTrickRepository = FileCommunityTrickRepository(),
        creatorID: String = "user-sat"
    ) {
        self.creatorID = creatorID
        workflow = CommunityTrickWorkflow(repository: repository)
    }

    var fieldProposals: [CommunityTrickProposal] {
        snapshot.proposals
            .filter { $0.status == .published }
            .sorted { $0.updatedAtISO8601 > $1.updatedAtISO8601 }
    }

    var myProposals: [CommunityTrickProposal] {
        snapshot.proposals
            .filter { $0.creatorID == creatorID }
            .sorted { $0.updatedAtISO8601 > $1.updatedAtISO8601 }
    }

    var reviewProposals: [CommunityTrickProposal] {
        snapshot.proposals
            .filter { $0.status == .submitted }
            .sorted { $0.updatedAtISO8601 < $1.updatedAtISO8601 }
    }

    func examples(for proposalID: String) -> [CommunityTrickExample] {
        snapshot.examples.filter { $0.proposalID == proposalID }
    }

    func evidenceCount(for proposalID: String) -> Int {
        snapshot.trainingEvidence.count { $0.proposalID == proposalID }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            snapshot = try await workflow.snapshot()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func create(
        name: String,
        description: String,
        coachingCue: String,
        aliases: [String]
    ) async -> Bool {
        do {
            _ = try await workflow.createProposal(
                creatorID: creatorID,
                name: name,
                description: description,
                coachingCue: coachingCue,
                aliases: aliases
            )
            section = .mine
            await load()
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    func submit(_ proposal: CommunityTrickProposal) async {
        do {
            _ = try await workflow.submitProposal(
                proposalID: proposal.id,
                actor: CommunityTrickActor(id: creatorID)
            )
            await load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func review(_ proposal: CommunityTrickProposal, decision: CommunityReviewDecision) async {
        do {
            _ = try await workflow.reviewProposal(
                proposalID: proposal.id,
                actor: CommunityTrickActor(id: "local-beta-moderator", role: .moderator),
                decision: decision,
                notes: "Local beta review"
            )
            await load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private static func message(for error: Error) -> String {
        if let workflowError = error as? CommunityTrickWorkflow.WorkflowError {
            return workflowError.errorDescription ?? "The trick could not be updated."
        }
        return error.localizedDescription
    }
}

/// A player-facing surface over the community trick workflow. It deliberately
/// keeps local moderation visible as a beta bench and never claims that an
/// approved capture has trained the runtime detector.
struct CommunityTrickExchangeView: View {
    @State private var model: CommunityTrickExchangeModel
    @State private var isCreating = false

    init(repository: any CommunityTrickRepository = FileCommunityTrickRepository()) {
        _model = State(initialValue: CommunityTrickExchangeModel(repository: repository))
    }

    var body: some View {
        @Bindable var model = model

        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.hazard)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    sectionPicker(selection: $model.section)
                    sectionIntro
                    proposalList
                }
                .padding(20)
                .padding(.bottom, 110)
            }
            .refreshable { await model.load() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.load() }
        .sheet(isPresented: $isCreating) {
            CommunityTrickComposerView(model: model)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Trick Exchange", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("TRICK\nEXCHANGE")
                    .font(.system(size: 39, weight: .black, design: .rounded))
                    .tracking(-1.8)
                Text("NAME IT. PROVE IT. PASS IT ON.")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.hazard)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                isCreating = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .black))
                    .frame(width: 50, height: 50)
            }
            .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
            .accessibilityLabel("Propose a new trick")
        }
    }

    private func sectionPicker(
        selection: Binding<CommunityTrickExchangeModel.Section>
    ) -> some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 19) {
            HStack(spacing: 4) {
                ForEach(CommunityTrickExchangeModel.Section.allCases) { section in
                    Button {
                        selection.wrappedValue = section
                    } label: {
                        Text(section.title)
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(
                                selection.wrappedValue == section
                                    ? KamikazeTheme.hazard.opacity(0.18)
                                    : .clear,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(
                        selection.wrappedValue == section
                            ? KamikazeTheme.frost
                            : KamikazeTheme.muted
                    )
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var sectionIntro: some View {
        switch model.section {
        case .field:
            exchangeNote(
                icon: "sparkles",
                title: "COMMUNITY TRICKS",
                detail: "Published ideas can collect labelled motion. They do not alter the detector automatically.",
                tint: KamikazeTheme.volt
            )
        case .mine:
            exchangeNote(
                icon: "square.and.pencil",
                title: "YOUR WORKBENCH",
                detail: "Draft the movement clearly, then send it to review when the definition feels right.",
                tint: KamikazeTheme.ion
            )
        case .review:
            exchangeNote(
                icon: "checkmark.seal",
                title: "LOCAL BETA REVIEW",
                detail: "This simulates moderation on this phone. Server roles and cloud review are not connected yet.",
                tint: KamikazeTheme.hazard
            )
        }
    }

    private func exchangeNote(icon: String, title: String, detail: String, tint: Color) -> some View {
        GlassSurface(role: .contentPanel, cornerRadius: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
    }

    @ViewBuilder
    private var proposalList: some View {
        if model.isLoading && model.snapshot.proposals.isEmpty {
            ProgressView()
                .tint(KamikazeTheme.volt)
                .frame(maxWidth: .infinity, minHeight: 210)
        } else {
            let proposals = visibleProposals
            if proposals.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(proposals) { proposal in
                        CommunityTrickProposalCard(
                            proposal: proposal,
                            exampleCount: model.examples(for: proposal.id).count,
                            evidenceCount: model.evidenceCount(for: proposal.id),
                            section: model.section,
                            onSubmit: { Task { await model.submit(proposal) } },
                            onReview: { decision in
                                Task { await model.review(proposal, decision: decision) }
                            }
                        )
                    }
                }
            }
        }
    }

    private var visibleProposals: [CommunityTrickProposal] {
        switch model.section {
        case .field: model.fieldProposals
        case .mine: model.myProposals
        case .review: model.reviewProposals
        }
    }

    private var emptyState: some View {
        GlassSurface(role: .interactiveCard, cornerRadius: 26) {
            VStack(spacing: 13) {
                Image(systemName: emptyIcon)
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(KamikazeTheme.hazard)
                Text(emptyTitle)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(emptyDetail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                    .multilineTextAlignment(.center)
                if model.section != .review {
                    Button("PROPOSE THE FIRST ONE") { isCreating = true }
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .padding(20)
        }
    }

    private var emptyIcon: String {
        switch model.section {
        case .field: "figure.skating"
        case .mine: "scribble.variable"
        case .review: "checkmark.circle"
        }
    }

    private var emptyTitle: String {
        switch model.section {
        case .field: "THE FIELD IS OPEN"
        case .mine: "NAME YOUR MOVE"
        case .review: "QUEUE CLEARED"
        }
    }

    private var emptyDetail: String {
        switch model.section {
        case .field: "A trick starts as a precise idea before it becomes detector evidence."
        case .mine: "Describe one movement other riders could repeat and recognize."
        case .review: "Submitted trick definitions will wait here for a decision."
        }
    }
}

private struct CommunityTrickProposalCard: View {
    let proposal: CommunityTrickProposal
    let exampleCount: Int
    let evidenceCount: Int
    let section: CommunityTrickExchangeModel.Section
    let onSubmit: () -> Void
    let onReview: (CommunityReviewDecision) -> Void

    var body: some View {
        GlassSurface(role: .interactiveCard, cornerRadius: 25) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(proposal.name.uppercased())
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .tracking(-0.8)
                        Text(proposal.description)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(proposal.status.label)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(proposal.status.tint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(proposal.status.tint.opacity(0.12), in: Capsule())
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .foregroundStyle(KamikazeTheme.ion)
                    Text(proposal.coachingCue)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !proposal.aliases.isEmpty {
                    Text(proposal.aliases.map { $0.uppercased() }.joined(separator: "  ·  "))
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                }

                Divider().overlay(.white.opacity(0.08))

                HStack(spacing: 16) {
                    metric(value: exampleCount, label: "CAPTURES")
                    metric(value: evidenceCount, label: "APPROVED")
                    Spacer(minLength: 0)
                    actionButtons
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if section == .mine && (proposal.status == .draft || proposal.status == .rejected) {
            Button("SEND TO REVIEW", action: onSubmit)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .adaptiveGlassButton(tint: KamikazeTheme.ion)
        } else if section == .review {
            HStack(spacing: 7) {
                Button(action: { onReview(.rejected) }) {
                    Image(systemName: "xmark")
                        .frame(width: 39, height: 39)
                }
                .adaptiveGlassButton(tint: KamikazeTheme.hazard)
                .accessibilityLabel("Reject proposal")

                Button(action: { onReview(.approved) }) {
                    Image(systemName: "checkmark")
                        .frame(width: 39, height: 39)
                }
                .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
                .accessibilityLabel("Publish proposal")
            }
        }
    }

    private func metric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 19, weight: .black, design: .rounded))
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
        }
    }
}

private struct CommunityTrickComposerView: View {
    let model: CommunityTrickExchangeModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var coachingCue = ""
    @State private var aliases = ""
    @State private var isSaving = false

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && coachingCue.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.hazard)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("NAME\nTHE MOVE")
                        .font(.system(size: 39, weight: .black, design: .rounded))
                        .tracking(-1.7)
                    Text("WRITE IT SO SOMEBODY ELSE CAN THROW IT.")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.hazard)

                    inputCard(title: "TRICK NAME", hint: "e.g. Corkscrew", text: $name)
                    textEditorCard(
                        title: "WHAT MOVES?",
                        hint: "Describe the phone's rotations and direction.",
                        text: $description,
                        minimumHeight: 92
                    )
                    textEditorCard(
                        title: "ONE COACHING CUE",
                        hint: "The shortest useful instruction.",
                        text: $coachingCue,
                        minimumHeight: 76
                    )
                    inputCard(
                        title: "OTHER NAMES  /  OPTIONAL",
                        hint: "Comma separated",
                        text: $aliases
                    )

                    GlassSurface(role: .contentPanel, cornerRadius: 18) {
                        Label(
                            "This saves a local draft. No sensor data or video is attached yet.",
                            systemImage: "lock.shield"
                        )
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                        .padding(13)
                    }

                    HStack(spacing: 10) {
                        Button("CANCEL") { dismiss() }
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .adaptiveGlassButton(tint: KamikazeTheme.muted)

                        Button(isSaving ? "SAVING…" : "SAVE DRAFT") {
                            isSaving = true
                            Task {
                                let didSave = await model.create(
                                    name: name,
                                    description: description,
                                    coachingCue: coachingCue,
                                    aliases: aliases
                                        .split(separator: ",")
                                        .map(String.init)
                                )
                                isSaving = false
                                if didSave { dismiss() }
                            }
                        }
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
                        .disabled(!canSave || isSaving)
                        .opacity(canSave ? 1 : 0.45)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func inputCard(title: String, hint: String, text: Binding<String>) -> some View {
        GlassSurface(role: .contentPanel, cornerRadius: 19) {
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel(title)
                TextField(hint, text: text)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .textInputAutocapitalization(.sentences)
                    .padding(.vertical, 6)
            }
            .padding(14)
        }
    }

    private func textEditorCard(
        title: String,
        hint: String,
        text: Binding<String>,
        minimumHeight: CGFloat
    ) -> some View {
        GlassSurface(role: .contentPanel, cornerRadius: 19) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(title)
                ZStack(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(hint)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted.opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: text)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: minimumHeight)
                }
            }
            .padding(14)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(KamikazeTheme.muted)
    }
}

private extension CommunityTrickProposalStatus {
    var label: String {
        switch self {
        case .draft: "DRAFT"
        case .submitted: "IN REVIEW"
        case .published: "PUBLISHED"
        case .rejected: "REVISE"
        }
    }

    var tint: Color {
        switch self {
        case .draft: KamikazeTheme.muted
        case .submitted: KamikazeTheme.ion
        case .published: KamikazeTheme.volt
        case .rejected: KamikazeTheme.hazard
        }
    }
}
