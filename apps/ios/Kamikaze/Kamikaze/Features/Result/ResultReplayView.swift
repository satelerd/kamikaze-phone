import KamikazeMotionCore
import SwiftUI

struct ResultReplayView: View {
    let primaryTitle: String
    /// Practice target. When set, the result compares the measured identity
    /// against it and offers one-tap landed/missed confirmation for the
    /// target trick. The replay and correction flow are identical to Play.
    let practiceTarget: BuiltInTrickID?
    let onAgain: () -> Void
    let onClose: () -> Void
    let onReview: (HumanAttemptReview) async -> NativeRunResult?
    /// Machine-readable prompt context for Follow. It is appended to human
    /// review notes so exported evidence retains the intended condition.
    let reviewContextNote: String?
    let requiresReviewBeforeAgain: Bool
    /// Saved-attempt contexts (History, Recent) pass this to allow permanent
    /// deletion. The immediate Play result does not.
    let onDelete: (() async -> Void)?
    /// Mathematical target frames for the practice ghost overlay; nil outside
    /// practice mode or for tricks without a validated definition.
    private let targetFrames: [ReplayFrame]?
    private let targetDefinition: TrickDefinition?
    /// Measured free-fall window of this attempt (accelerometer-detected);
    /// nil when no sustained free fall exists (e.g. a spin in the hand).
    private let freefall: FreefallWindow?
    @State private var displayedResult: NativeRunResult
    @State private var replay: ReplayController
    @State private var showsCorrection = false
    @State private var isConfirming = false
    @State private var showsDeleteConfirmation = false
    @AppStorage(BetaFlags.verticalArc) private var verticalArc = true
    @AppStorage(BetaFlags.airBonus) private var airBonusEnabled = true
    @AppStorage(BetaFlags.resultMetric) private var resultMetricRaw = ResultMetricMode.default.rawValue
    @Environment(FeedbackCoordinator.self) private var feedback

    init(
        result: NativeRunResult,
        primaryTitle: String = "THROW AGAIN",
        practiceTarget: BuiltInTrickID? = nil,
        onAgain: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onReview: @escaping (HumanAttemptReview) async -> NativeRunResult?,
        reviewContextNote: String? = nil,
        requiresReviewBeforeAgain: Bool = false,
        onDelete: (() async -> Void)? = nil
    ) {
        self.primaryTitle = primaryTitle
        self.practiceTarget = practiceTarget
        self.onAgain = onAgain
        self.onClose = onClose
        self.onReview = onReview
        self.reviewContextNote = reviewContextNote
        self.requiresReviewBeforeAgain = requiresReviewBeforeAgain
        self.onDelete = onDelete
        let definition = practiceTarget.flatMap { target in
            TrickCatalog.provisional(gripHand: .right).definitions.first { $0.id == target }
        }
        targetDefinition = definition
        targetFrames = definition.map { TargetMotionGenerator.frames(for: $0) }
        _displayedResult = State(initialValue: result)
        _replay = State(initialValue: ReplayController(
            payload: result.capture.samplePayload,
            boundaries: result.capture.attempt.boundaries
        ))
        // Same frame build the controller performs, so window timestamps and
        // playhead share one timebase.
        freefall = ReplayBuilder.freefallWindow(in: ReplayBuilder.normalized(
            ReplayBuilder.buildFrames(
                payload: result.capture.samplePayload,
                boundaries: result.capture.attempt.boundaries
            )
        ))
    }

    var body: some View {
        ZStack {
            // Keep the field expressive but independent from the 60 Hz
            // replay playhead. Reading the playhead at this parent level
            // invalidated the entire result hierarchy on every frame.
            SlipstreamField(
                accent: accent,
                energy: resultFieldEnergy
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Spacer()
                        if onDelete != nil {
                            Button("Delete", systemImage: "trash") { showsDeleteConfirmation = true }
                                .labelStyle(.iconOnly)
                                .adaptiveGlassButton(tint: KamikazeTheme.hazard)
                        }
                        Button("Close", systemImage: "xmark") { onClose() }
                            .labelStyle(.iconOnly)
                            .adaptiveGlassButton()
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(displayedResult.displayName)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .tracking(-1.5)
                        Spacer()
                        Text(primaryMetricValue)
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(accent)
                    }
                    Text(scoreExplanation)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)

                    if let proposedName = displayedResult.proposedName {
                        Text("PROPOSED MATCH  /  \(proposedName.uppercased())")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.hazard)
                    }

                    if let practiceTarget {
                        practiceBanner(target: practiceTarget)
                    }

                    ReplayPhoneView(
                        controller: replay,
                        accent: accent,
                        targetFrames: targetFrames,
                        arcWindow: verticalArc ? freefall : nil
                    )

                    if let practiceTarget, displayedResult.humanReview == nil {
                        practiceConfirmRow(target: practiceTarget)
                    }

                    Button(primaryTitle) { onAgain() }
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 122)
                        .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.ion)
                        .disabled(requiresReviewBeforeAgain && displayedResult.humanReview == nil)

                    scoreBreakdownCard

                    GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
                        VStack(spacing: 14) {
                            HStack {
                                stat("IDENTITY", displayedResult.identityLabel)
                                stat("FIT", displayedResult.displayedFit.map(String.init) ?? "—")
                                stat("SCORE STATE", displayedResult.evaluation.score?.verification.label ?? "REVIEW")
                            }
                            Divider().overlay(.white.opacity(0.08))
                            HStack {
                                stat("DURATION", "\(displayedResult.durationMs) MS")
                                if let freefall {
                                    stat("AIR", "\(Int((freefall.durationS * 1_000).rounded())) MS")
                                    stat("EST. PEAK", "\(Int((freefall.peakHeightM * 100).rounded())) CM")
                                }
                                stat("EVIDENCE", "\(displayedResult.capture.samplePayload.samples.count) SAMPLES")
                            }
                        }
                        .padding(16)
                    }

                    // Deliberately far from THROW AGAIN so a fast re-throw tap
                    // can never land on the correction flow by accident.
                    Button(displayedResult.humanReview == nil ? "NOT QUITE?" : "EDIT HUMAN LABEL") {
                        showsCorrection = true
                    }
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .adaptiveGlassButton(tint: KamikazeTheme.hazard)
                    .padding(.top, 26)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .onAppear { replay.play() }
        .onDisappear { replay.pause() }
        .confirmationDialog(
            "Delete this attempt?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete raw evidence and analysis", role: .destructive) {
                Task { await onDelete?() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This permanently removes the sensor evidence, its analysis and its summary. Statistics and practice progress update immediately.")
        }
        .sheet(isPresented: $showsCorrection) {
            ResultCorrectionView(result: displayedResult, contextNote: reviewContextNote) { review in
                guard let updated = await onReview(review) else { return false }
                displayedResult = updated
                return true
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var accent: Color {
        if let outcome = displayedResult.humanReview?.outcome {
            return outcome == .landed ? KamikazeTheme.volt : KamikazeTheme.hazard
        }
        return displayedResult.match.status == .recognized ? KamikazeTheme.volt : KamikazeTheme.hazard
    }

    private var resultFieldEnergy: Double {
        guard let peak = displayedResult.match.features?.peakGyroDps else { return 0.18 }
        return min(1, max(0.18, peak / ExperienceCoordinator.fullScaleGyroDps * 0.55))
    }

    private var scoreExplanation: String {
        if resultMetric == .legacyFit {
            return "FIT · similarity to the selected trick definition, not landing quality or probability."
        }
        if let score = displayedResult.evaluation.score {
            let comparison = resultMetric == .compare
                ? " · FIT \(displayedResult.displayedFit.map(String.init) ?? "—")"
                : ""
            let air = airBonusPoints > 0 ? " · +\(airBonusPoints) estimated air" : ""
            return "THROW SCORE · technique \(score.value)\(air) · \(score.verification.label.lowercased())\(comparison)."
        }
        return "NO SCORE YET · confirm the trick and outcome without changing its raw sensor evidence."
    }

    private var resultMetric: ResultMetricMode {
        ResultMetricMode(rawValue: resultMetricRaw) ?? .default
    }

    private var primaryMetricValue: String {
        switch resultMetric {
        case .legacyFit:
            displayedResult.displayedFit.map(String.init) ?? "—"
        case .gameScore, .compare:
            displayedGameScore.map(String.init) ?? "—"
        }
    }

    private var displayedGameScore: Int? {
        guard let base = displayedResult.evaluation.score?.value else { return nil }
        return min(100, base + airBonusPoints)
    }

    /// Experimental reward: one point per estimated 5 cm, capped at 10.
    /// It never mutates the persisted v1 technique score.
    private var airBonusPoints: Int {
        guard airBonusEnabled, let freefall else { return 0 }
        return min(10, max(0, Int((freefall.peakHeightM / 0.05).rounded())))
    }

    @ViewBuilder
    private var scoreBreakdownCard: some View {
        if let score = displayedResult.evaluation.score {
            GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SCORE BREAKDOWN")
                        Spacer()
                        Text("\(displayedGameScore ?? score.value) / 100")
                            .foregroundStyle(accent)
                    }
                    .font(.system(size: 11, weight: .black, design: .monospaced))

                    scoreRow("COMPLETION", value: score.components.completion, weight: 35,
                             detail: "required rotation reached")
                    scoreRow("PURITY", value: score.components.purity, weight: 20,
                             detail: "rotation stayed on intended axes")
                    scoreRow("CATCH", value: score.components.stability, weight: 30,
                             detail: "phone stabilized after capture")
                    scoreRow("FLOW", value: score.components.flow, weight: 15,
                             detail: "useful rotation vs extra motion")

                    Divider().overlay(.white.opacity(0.1))
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AIR · ESTIMATED")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                            Text(freefall.map {
                                "\(Int(($0.peakHeightM * 100).rounded())) cm from \(Int(($0.durationS * 1_000).rounded())) ms air time"
                            } ?? "No reliable free-fall window")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(KamikazeTheme.muted)
                        }
                        Spacer()
                        Text(airBonusEnabled ? "+\(airBonusPoints)" : "OFF")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.volt)
                    }
                    Text("Height is inferred from measured air time under a ballistic model; it is not direct vertical tracking. Change AIR BONUS in Beta.")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                .padding(16)
            }
        }
    }

    private func scoreRow(
        _ title: String,
        value: Double,
        weight: Double,
        detail: String
    ) -> some View {
        let points = Int((value * weight).rounded())
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                Text("\(Int((value * 100).rounded()))% · \(detail)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            Spacer()
            Text("\(points) / \(Int(weight))")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
        }
    }

    private func practiceBanner(target: BuiltInTrickID) -> some View {
        let measured = displayedResult.evaluation.identity.trickID
        let onTarget = measured == target
        let coachMessage = targetDefinition.map {
            PracticeCoach.reviewMessage(
                features: displayedResult.match.features,
                definition: $0,
                recognizedTrickID: measured
            )
        }
        return GlassSurface(role: .contentPanel, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TARGET")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                        Text(target.displayName)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                    }
                    Spacer()
                    Text(onTarget ? "ON TARGET" : (measured == nil ? "NOT RECOGNIZED" : "DIFFERENT TRICK"))
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(onTarget ? KamikazeTheme.volt : KamikazeTheme.hazard)
                }
                if let coachMessage {
                    Text("COACH  ·  \(coachMessage)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(onTarget ? KamikazeTheme.volt : KamikazeTheme.hazard)
                }
            }
            .padding(16)
        }
    }

    /// One-tap ground truth for the attempted target. Both paths store a
    /// normal `HumanAttemptReview`; `NOT QUITE?` remains for anything else.
    private func practiceConfirmRow(target: BuiltInTrickID) -> some View {
        HStack(spacing: 10) {
            Button("LANDED IT") {
                confirm(HumanAttemptReview(
                    trickID: target,
                    outcome: .landed,
                    notes: reviewContextNote ?? ""
                ))
            }
            .font(.system(size: 13, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 52)
            .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)

            Button("MISSED") {
                confirm(HumanAttemptReview(
                    trickID: target,
                    outcome: .missed,
                    notes: reviewContextNote ?? ""
                ))
            }
            .font(.system(size: 13, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 52)
            .adaptiveGlassButton(tint: KamikazeTheme.hazard)
        }
        .disabled(isConfirming)
    }

    private func confirm(_ review: HumanAttemptReview) {
        guard !isConfirming else { return }
        isConfirming = true
        Task {
            if let updated = await onReview(review) {
                displayedResult = updated
                switch review.outcome {
                case .landed:
                    let fit = updated.displayedFitValue ?? 0
                    feedback.play(.landed(scoreBand: fit >= 0.9 ? 2 : (fit >= 0.75 ? 1 : 0)))
                case .missed:
                    feedback.play(.missed)
                case .unclear, .noAttempt:
                    break
                }
            }
            isConfirming = false
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ResultCorrectionView: View {
    let result: NativeRunResult
    let contextNote: String?
    let onSave: (HumanAttemptReview) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTrick: BuiltInTrickID?
    @State private var outcome: HumanAttemptOutcome
    @State private var notes: String
    @State private var isSaving = false
    @State private var saveFailed = false

    init(
        result: NativeRunResult,
        contextNote: String? = nil,
        onSave: @escaping (HumanAttemptReview) async -> Bool
    ) {
        self.result = result
        self.contextNote = contextNote
        self.onSave = onSave
        _selectedTrick = State(initialValue: result.humanReview?.trickID ?? result.match.candidates.first?.definition.id)
        _outcome = State(initialValue: result.humanReview?.outcome
            ?? (result.match.status == .recognized ? .landed : .unclear))
        _notes = State(initialValue: result.humanReview?.notes ?? "")
    }

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.hazard)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("WHAT ACTUALLY\nHAPPENED?")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-1.4)
                    Text("This corrects the saved interpretation without changing the original sensor evidence.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)

                    GlassSurface(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("OUTCOME")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.muted)
                            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
                                ForEach(HumanAttemptOutcome.allCases, id: \.self) { value in
                                    selectionButton(value.displayName, selected: outcome == value) {
                                        outcome = value
                                        if value == .noAttempt { selectedTrick = nil }
                                    }
                                }
                            }

                            if outcome != .noAttempt {
                                Text("TRICK ATTEMPTED")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
                                    ForEach(BuiltInTrickID.correctableCases, id: \.self) { trick in
                                        selectionButton(trick.displayName, selected: selectedTrick == trick) {
                                            selectedTrick = trick
                                        }
                                    }
                                }
                            }

                            TextField("Optional note", text: $notes, axis: .vertical)
                                .lineLimit(2 ... 4)
                                .padding(12)
                                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(18)
                    }

                    if saveFailed {
                        Text("Could not save the correction. Your raw attempt is still safe.")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(KamikazeTheme.hazard)
                    }

                    Button("CONFIRM CORRECTION") {
                        let review = HumanAttemptReview(
                            trickID: selectedTrick,
                            outcome: outcome,
                            notes: [contextNote, notes]
                                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                                .joined(separator: " | ")
                        )
                        isSaving = true
                        saveFailed = false
                        Task {
                            if await onSave(review) {
                                dismiss()
                            } else {
                                isSaving = false
                                saveFailed = true
                            }
                        }
                    }
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
                    .disabled(isSaving || (outcome != .noAttempt && selectedTrick == nil))
                }
                .padding(20)
                .padding(.bottom, 36)
            }
        }
    }

    private func selectionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(selected ? Color.black : KamikazeTheme.frost)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? KamikazeTheme.volt : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(selected ? 0.35 : 0.1)))
        }
        .buttonStyle(.plain)
    }
}
