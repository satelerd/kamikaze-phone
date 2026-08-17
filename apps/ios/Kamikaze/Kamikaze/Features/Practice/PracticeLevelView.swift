import KamikazeMotionCore
import SwiftUI

/// One focused lesson. LEARN owns the mathematical target; TRY owns the live
/// sensor and resolves into an inline target-vs-player comparison. Practice
/// never presents the generic Play result because the lesson question is much
/// simpler: "was this the exact target trick?"
struct PracticeLevelView: View {
    let node: PracticeTrickNode
    let pair: PracticePair

    private let targetFrames: [ReplayFrame]

    @State private var run: NativeRunModel
    @State private var progressModel = PracticeModel()
    @State private var targetReplay: ReplayController
    @State private var resultReplay: ReplayController?
    @State private var lessonStep = PracticeLessonStep.learn
    @State private var baselineReps: Int?
    @State private var sessionSuccessIDs: Set<String> = []
    @State private var isApplyingReview = false

    @Environment(ExperienceCoordinator.self) private var experience
    @Environment(FeedbackCoordinator.self) private var feedback

    init(node: PracticeTrickNode, pair: PracticePair) {
        self.node = node
        self.pair = pair
        _run = State(initialValue: NativeRunModel(expectedTrickID: node.trickID))
        let definition = TrickCatalog.provisional(gripHand: .right)
            .definitions.first { $0.id == node.trickID }
        let frames = definition.map { TargetMotionGenerator.frames(for: $0) } ?? []
        targetFrames = frames
        _targetReplay = State(initialValue: ReplayController(frames: frames))
    }

    private var active: Bool {
        switch run.phase {
        case .armed, .motion, .settling: true
        case .ready, .result, .unknown, .failed: false
        }
    }

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: stageAccent)
            ScrollView {
                practiceContent
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            run.start()
            targetReplay.setSpeed(.half)
            targetReplay.play()
            await refreshProgress(establishingBaseline: true)
        }
        .onChange(of: targetReplay.state) { _, state in
            guard state == .ended, showsTarget else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                guard showsTarget, targetReplay.state == .ended else { return }
                targetReplay.seek(toProgress: 0)
                targetReplay.play()
            }
        }
        .onChange(of: run.phase) { _, phase in
            experience.report(phase: phase.experiencePhase)
            reactToPhase(phase)
        }
        .onChange(of: run.result?.id) { _, resultID in
            guard resultID != nil, let result = run.result else {
                resultReplay?.pause()
                resultReplay = nil
                return
            }
            resolveInline(result)
        }
        .onDisappear {
            targetReplay.pause()
            resultReplay?.pause()
            run.stop()
            experience.report(phase: .idle)
        }
    }

    private var practiceContent: some View {
        VStack(spacing: 14) {
            trainingTape
            lessonHeader

            ZStack {
                if let result = run.result, let resultReplay {
                    ReplayPhoneScene(
                        controller: resultReplay,
                        accent: resultAccent(for: result),
                        targetFrames: targetFrames
                    )
                    stageBadge(
                        isSuccessful(result) ? "ON TARGET" : "TRY AGAIN",
                        color: resultAccent(for: result)
                    )
                } else if showsTarget {
                    ReplayPhoneScene(
                        controller: targetReplay,
                        accent: KamikazeTheme.volt,
                        appearanceOverride: .demo,
                        screenLabel: "TARGET"
                    )
                    stageBadge("TARGET · PREVIEW", color: KamikazeTheme.volt)
                } else {
                    LiveRunStage(run: run, accent: stageAccent, initialZoom: 0.55)
                }
            }
            .frame(height: 365)
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            if showsTarget {
                replayTransport(targetReplay, tint: KamikazeTheme.volt, label: "TARGET")
                lessonBrief
            } else if let result = run.result, let resultReplay {
                replayTransport(resultReplay, tint: resultAccent(for: result), label: "YOU")
            }

            VStack(spacing: 4) {
                Text(statusTitle)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(statusColor)
                Text(statusDetail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .multilineTextAlignment(.center)

            Button(action: primaryAction) {
                Text(primaryActionTitle)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 66)
            }
            .adaptiveGlassButton(
                prominent: true,
                tint: active ? KamikazeTheme.hazard : primaryTint
            )

            if let result = run.result {
                Button {
                    submitFeedback(for: result)
                } label: {
                    Text(isSuccessful(result) ? "NOT QUITE?" : "I LANDED THE TARGET")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .adaptiveGlassButton(tint: isSuccessful(result) ? KamikazeTheme.hazard : KamikazeTheme.volt)
                .disabled(isApplyingReview)
            }
        }
    }

    private var lessonHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(node.trickID.displayName)
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .tracking(-1.2)
                Text(node.coachingCue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(min(displayedReps, PracticeProgress.repsToUnlock))/\(PracticeProgress.repsToUnlock)")
                    .font(.system(size: 35, weight: .black, design: .rounded))
                    .tracking(-1.8)
                    .foregroundStyle(displayedReps >= PracticeProgress.repsToUnlock ? KamikazeTheme.volt : KamikazeTheme.frost)
                Text("TO PASS")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(min(displayedReps, PracticeProgress.repsToUnlock)) of \(PracticeProgress.repsToUnlock) reps to pass")
        }
    }

    private var trainingTape: some View {
        HStack(spacing: 7) {
            ForEach(PracticeLessonStep.allCases, id: \.self) { step in
                Button {
                    select(step)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule()
                            .fill(step == lessonStep ? KamikazeTheme.volt : .white.opacity(0.13))
                            .frame(height: step == lessonStep ? 4 : 2)
                        Text(step.label)
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(step == lessonStep ? KamikazeTheme.frost : KamikazeTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("practice-step-\(step.label.lowercased())")
                .accessibilityLabel("\(step.label)\(step == lessonStep ? ", current step" : "")")
            }
        }
    }

    private func stageBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(color, in: Capsule())
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
    }

    private var lessonBrief: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 18) {
            HStack(spacing: 14) {
                Image(systemName: "move.3d")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(KamikazeTheme.ion)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("READ THE ROTATION")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                    Text("Orbit the target iPhone. Notice its axis and direction, then switch to Try.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
        }
    }

    private func replayTransport(
        _ controller: ReplayController,
        tint: Color,
        label: String
    ) -> some View {
        GlassSurface(role: .transport, cornerRadius: 18) {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(tint)
                Button {
                    controller.togglePlayback()
                } label: {
                    Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(tint)
                        .frame(width: 34, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.state == .playing ? "Pause \(label.lowercased())" : "Play \(label.lowercased())")

                Slider(
                    value: Binding(
                        get: { controller.progress },
                        set: { controller.seek(toProgress: $0) }
                    ),
                    in: 0 ... 1
                )
                .tint(tint)
                .accessibilityLabel("\(label) motion position")

                Menu(controller.speed.label) {
                    ForEach(ReplayController.PlaybackSpeed.allCases) { speed in
                        Button(speed.label) { controller.setSpeed(speed) }
                    }
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .frame(minWidth: 40, minHeight: 38)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private var showsTarget: Bool {
        lessonStep == .learn && run.result == nil
    }

    private var persistedReps: Int {
        progressModel.progress.qualifyingReps(for: node.trickID)
    }

    /// Persistence lands just after the result animation. The session overlay
    /// makes the counter react immediately, while `max` prevents double-counts
    /// once the derived summary catches up.
    private var displayedReps: Int {
        max(persistedReps, (baselineReps ?? persistedReps) + sessionSuccessIDs.count)
    }

    private func isSuccessful(_ result: NativeRunResult) -> Bool {
        PracticeAttemptJudgement.isSuccess(
            target: node.trickID,
            automaticStatus: result.match.status,
            automaticTrickID: result.match.candidates.first?.definition.id,
            humanReview: result.humanReview
        )
    }

    private func select(_ step: PracticeLessonStep) {
        guard step != lessonStep || run.result != nil || active else { return }
        if active {
            run.cancel()
            feedback.play(.cancelled)
        } else if run.result != nil {
            run.dismissResult()
        }
        resultReplay?.pause()
        resultReplay = nil
        lessonStep = step
        if step == .learn {
            targetReplay.seek(toProgress: 0)
            targetReplay.setSpeed(.half)
            targetReplay.play()
        } else {
            targetReplay.pause()
        }
    }

    private func primaryAction() {
        if active {
            run.cancel()
            feedback.play(.cancelled)
        } else if run.result != nil {
            resultReplay?.pause()
            resultReplay = nil
            lessonStep = .tryIt
            run.dismissResultAndRearm()
        } else if lessonStep == .learn {
            select(.tryIt)
        } else {
            run.arm()
        }
    }

    private var primaryActionTitle: String {
        if active { return "CANCEL" }
        if let result = run.result { return isSuccessful(result) ? "NEXT REP" : "TRY AGAIN" }
        return lessonStep == .learn ? "TRY THIS TRICK" : "START PRACTICE"
    }

    private var primaryTint: Color {
        if let result = run.result { return resultAccent(for: result) }
        return lessonStep == .learn ? KamikazeTheme.volt : KamikazeTheme.ion
    }

    private var statusTitle: String {
        if let result = run.result {
            if isSuccessful(result) { return "NAILED IT" }
            if let detected = result.evaluation.identity.trickID {
                return "THAT WAS \(detected.displayName.uppercased())"
            }
            return "NOT THE TARGET"
        }
        if lessonStep == .learn { return "WATCH THE TARGET" }
        return switch run.phase {
        case .ready: displayedReps >= PracticeProgress.repsToUnlock ? "PASSED — KEEP RIDING" : "READY TO TRY?"
        case .armed: "THROW WHEN READY"
        case .motion: "TRICK IN MOTION"
        case .settling: "HOLD THE CATCH"
        case .result: "CHECKING TARGET"
        case .unknown: "NOT THE TARGET"
        case let .failed(message): "SENSOR ERROR\n\(message)"
        }
    }

    private var statusDetail: String {
        if let result = run.result {
            return isSuccessful(result)
                ? "Exact \(node.trickID.displayName) match. Rep counted."
                : "This rep does not count. The target is \(node.trickID.displayName)."
        }
        if lessonStep == .learn { return node.coachingCue }
        return switch run.phase {
        case .ready: "Only an exact target match advances the counter."
        case .armed: "Throw the \(node.trickID.displayName)."
        case .motion: "Catch it and hold still."
        case .settling: "Keep it steady."
        case .result: "Comparing against the target."
        case .unknown: "Nothing was guessed and no rep was counted."
        case .failed: "Reconnect motion access, then try again."
        }
    }

    private var statusColor: Color {
        guard let result = run.result else { return KamikazeTheme.frost }
        return resultAccent(for: result)
    }

    private var stageAccent: Color {
        if let result = run.result { return resultAccent(for: result) }
        return switch run.phase {
        case .motion, .settling: KamikazeTheme.hazard
        case .unknown, .failed: KamikazeTheme.hazard
        case .ready, .armed, .result: lessonStep == .learn ? KamikazeTheme.volt : KamikazeTheme.ion
        }
    }

    private func resultAccent(for result: NativeRunResult) -> Color {
        isSuccessful(result) ? KamikazeTheme.volt : KamikazeTheme.hazard
    }

    private func resolveInline(_ result: NativeRunResult) {
        lessonStep = .tryIt
        targetReplay.pause()
        let replay = ReplayController(
            payload: result.capture.samplePayload,
            boundaries: result.capture.attempt.boundaries
        )
        replay.setSpeed(.half)
        resultReplay = replay
        replay.play()
        if isSuccessful(result) {
            sessionSuccessIDs.insert(result.id)
        } else {
            sessionSuccessIDs.remove(result.id)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            await refreshProgress(establishingBaseline: false)
        }
    }

    private func submitFeedback(for result: NativeRunResult) {
        guard !isApplyingReview else { return }
        isApplyingReview = true
        let detectorWasSuccessful = isSuccessful(result)
        let review = HumanAttemptReview(
            trickID: node.trickID,
            outcome: detectorWasSuccessful ? .missed : .landed,
            notes: "practice-inline-v1 target=\(node.trickID.rawValue)"
        )
        Task { @MainActor in
            defer { isApplyingReview = false }
            guard let updated = await run.applyHumanReview(review) else { return }
            if isSuccessful(updated) {
                sessionSuccessIDs.insert(updated.id)
            } else {
                sessionSuccessIDs.remove(updated.id)
            }
            await refreshProgress(establishingBaseline: false)
        }
    }

    private func refreshProgress(establishingBaseline: Bool) async {
        await progressModel.refresh()
        if establishingBaseline || baselineReps == nil {
            baselineReps = persistedReps
        }
    }

    /// Same ordering rule as Play: armed tick before the evidence window;
    /// target-specific success audio only after capture closure.
    private func reactToPhase(_ phase: NativeRunPhase) {
        switch phase {
        case .armed:
            feedback.play(.armed)
            feedback.evidenceWindowActive = true
        case .motion, .settling:
            feedback.evidenceWindowActive = true
        case .result:
            feedback.evidenceWindowActive = false
            feedback.play(.catchResolved)
            feedback.playDetectionSound(success: run.result.map(isSuccessful) ?? false)
        case .unknown:
            feedback.evidenceWindowActive = false
            feedback.play(.needsReview)
            feedback.playDetectionSound(success: false)
        case .ready, .failed:
            feedback.evidenceWindowActive = false
        }
    }
}
