import KamikazeMotionCore
import SwiftUI

/// One practice level: target briefing, the same live capture loop as Play
/// (shared engine, shared persistence) and the shared result/replay screen in
/// practice mode.
struct PracticeLevelView: View {
    let node: PracticeTrickNode
    let pair: PracticePair

    @State private var run: NativeRunModel
    @State private var progressModel = PracticeModel()
    /// Mathematical target animation, looped while the level is at rest.
    @State private var targetReplay: ReplayController
    @State private var lessonStep = PracticeLessonStep.learn

    init(node: PracticeTrickNode, pair: PracticePair) {
        self.node = node
        self.pair = pair
        _run = State(initialValue: NativeRunModel(expectedTrickID: node.trickID))
        let definition = TrickCatalog.provisional(gripHand: .right)
            .definitions.first { $0.id == node.trickID }
        let frames = definition.map { TargetMotionGenerator.frames(for: $0) } ?? []
        _targetReplay = State(initialValue: ReplayController(frames: frames))
    }

    private var active: Bool {
        switch run.phase {
        case .armed, .motion, .settling: true
        case .ready, .result, .unknown, .failed: false
        }
    }

    @Environment(ExperienceCoordinator.self) private var experience
    @Environment(FeedbackCoordinator.self) private var feedback

    var body: some View {
        ZStack {
            if run.result == nil {
                ExperienceFieldBackground()
                practiceContent
            } else {
                // ResultReplayView owns the only active RealityView/Metal
                // field while its full-screen cover is presented.
                KamikazeTheme.pitch.ignoresSafeArea()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            run.start()
            targetReplay.setSpeed(.half)
            targetReplay.play()
            await progressModel.refresh()
        }
        .onChange(of: targetReplay.state) { _, state in
            // The demonstration loops while at rest, with a beat between
            // repetitions so each rep reads as its own throw.
            if state == .ended, showsTarget {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    guard showsTarget, targetReplay.state == .ended else { return }
                    targetReplay.seek(toProgress: 0)
                    targetReplay.play()
                }
            }
        }
        .onDisappear {
            targetReplay.pause()
            run.stop()
            experience.report(phase: .idle)
        }
        .onChange(of: run.phase) { _, phase in
            experience.report(phase: phase.experiencePhase)
            reactToPhase(phase)
        }
        .onChange(of: run.result?.id) { _, resultID in
            if resultID != nil {
                lessonStep = .review
                targetReplay.pause()
            } else if lessonStep != .tryIt {
                targetReplay.play()
            }
        }
        .fullScreenCover(item: Binding(
            get: { run.result },
            set: { if $0 == nil { run.dismissResult() } }
        )) { result in
            ResultReplayView(
                result: result,
                primaryTitle: "TRY AGAIN",
                practiceTarget: node.trickID,
                onAgain: {
                    lessonStep = .tryIt
                    run.dismissResultAndRearm()
                },
                onClose: {
                    lessonStep = .tryIt
                    run.dismissResult()
                },
                onReview: { review in
                    let updated = await run.applyHumanReview(review)
                    await progressModel.refresh()
                    return updated
                }
            )
        }
        .onChange(of: run.result == nil) { _, dismissed in
            if dismissed { Task { await progressModel.refresh() } }
        }
    }

    private var practiceContent: some View {
        VStack(spacing: 14) {
            trainingTape

            VStack(alignment: .leading, spacing: 6) {
                Text(node.trickID.displayName)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(-1.2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(node.coachingCue)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ZStack {
                if showsTarget {
                    // Mathematical demonstration on a clearly different
                    // DEMO phone — never the player's own configuration.
                    ReplayPhoneScene(
                        controller: targetReplay,
                        accent: KamikazeTheme.volt,
                        appearanceOverride: .demo,
                        screenLabel: "IDEAL"
                    )
                    Text("DEMO PHONE · TARGET MOTION")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(KamikazeTheme.volt, in: Capsule())
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    LiveRunStage(run: run, accent: accent, initialZoom: 0.55)
                }
            }
            .frame(maxHeight: 380)

            if lessonStep == .follow, !active {
                followTransport
            } else if lessonStep == .tryIt || active {
                RunTelemetryHUD(
                    run: run,
                    leadingTitle: "REPS",
                    leadingValue: "\(min(reps, PracticeProgress.repsToUnlock))/\(PracticeProgress.repsToUnlock)",
                    showsGyro: false
                )
            } else {
                lessonBrief
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(-0.8)
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .multilineTextAlignment(.center)

            Button {
                if lessonStep == .learn {
                    lessonStep = .follow
                    targetReplay.seek(toProgress: 0)
                    targetReplay.setSpeed(.quarter)
                    targetReplay.play()
                } else if lessonStep == .follow {
                    lessonStep = .tryIt
                    targetReplay.pause()
                } else if active {
                    run.cancel()
                    feedback.play(.cancelled)
                } else {
                    run.arm()
                }
            } label: {
                Text(primaryActionTitle)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 66)
            }
            .adaptiveGlassButton(
                prominent: true,
                tint: active ? KamikazeTheme.hazard : (lessonStep == .follow ? KamikazeTheme.volt : KamikazeTheme.ion)
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }

    private var reps: Int {
        progressModel.progress.qualifyingReps(for: node.trickID)
    }

    /// The target demo owns the stage only while the level is at rest; from
    /// ARMED onward the live pose is the hero.
    private var showsTarget: Bool {
        !active && (lessonStep == .learn || lessonStep == .follow)
    }

    private var trainingTape: some View {
        HStack(spacing: 5) {
            ForEach(PracticeLessonStep.allCases, id: \.self) { step in
                let activeStep = step == lessonStep
                let complete = step.isComplete(relativeTo: lessonStep)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(activeStep ? KamikazeTheme.volt : (complete ? KamikazeTheme.ion : .white.opacity(0.12)))
                        .frame(height: activeStep ? 4 : 2)
                    Text(step.label)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(activeStep ? KamikazeTheme.frost : KamikazeTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(step.label)\(activeStep ? ", current step" : (complete ? ", complete" : ""))")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var lessonBrief: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 18) {
            HStack(spacing: 14) {
                Image(systemName: lessonStep == .learn ? "move.3d" : "hand.draw.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(lessonStep == .learn ? KamikazeTheme.ion : KamikazeTheme.volt)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(lessonStep == .learn ? "READ THE ROTATION" : "TRACE IT WITH YOUR HAND")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                    Text(lessonStep == .learn
                        ? "Orbit the demo phone. Notice the axis and the direction before copying it."
                        : "Keep hold of your phone and mirror the ideal motion slowly. No throw yet.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
        }
    }

    private var followTransport: some View {
        GlassSurface(role: .transport, cornerRadius: 18) {
            HStack(spacing: 12) {
                Button {
                    targetReplay.togglePlayback()
                } label: {
                    Image(systemName: targetReplay.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(KamikazeTheme.volt)
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(targetReplay.state == .playing ? "Pause target" : "Play target")

                Slider(
                    value: Binding(
                        get: { targetReplay.progress },
                        set: { targetReplay.seek(toProgress: $0) }
                    ),
                    in: 0 ... 1
                )
                .tint(KamikazeTheme.volt)
                .accessibilityLabel("Target motion position")

                Menu(targetReplay.speed.label) {
                    ForEach(ReplayController.PlaybackSpeed.allCases) { speed in
                        Button(speed.label) { targetReplay.setSpeed(speed) }
                    }
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .frame(minWidth: 42, minHeight: 38)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    private var primaryActionTitle: String {
        if active { return "CANCEL" }
        return switch lessonStep {
        case .learn: "SHOW ME SLOWLY"
        case .follow: "I'VE GOT IT — TRY"
        case .tryIt, .review: "START PRACTICE"
        }
    }

    /// Same ordering rule as Play: armed tick before the window opens,
    /// result cues only after capture closure.
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
            // `result` is published before `phase` in NativeRunModel, so the
            // match status is already readable here.
            feedback.playDetectionSound(success: run.result?.match.status == .recognized)
        case .unknown:
            feedback.evidenceWindowActive = false
            feedback.play(.needsReview)
            feedback.playDetectionSound(success: false)
        case .ready, .failed:
            feedback.evidenceWindowActive = false
        }
    }

    private var accent: Color {
        switch run.phase {
        case .motion, .settling: KamikazeTheme.hazard
        case .result: KamikazeTheme.volt
        case .unknown, .failed: KamikazeTheme.hazard
        case .ready, .armed: KamikazeTheme.ion
        }
    }

    private var title: String {
        if !active, lessonStep == .learn { return "WATCH THE AXIS" }
        if !active, lessonStep == .follow { return "FOLLOW — DON'T THROW YET" }
        return switch run.phase {
        case .ready: progressModel.progress.isMastered(node.trickID) ? "MASTERED — KEEP RIDING" : "READY TO TRY?"
        case .armed: "THROW WHEN READY"
        case .motion: "TRICK IN MOTION"
        case .settling: "HOLD THE CATCH"
        case .result: "CAUGHT"
        case .unknown: "CHECK THE THROW"
        case let .failed(message): "SENSOR ERROR\n\(message)"
        }
    }

    private var detail: String {
        if !active, lessonStep == .learn { return node.coachingCue }
        if !active, lessonStep == .follow { return "Scrub, slow it down and mirror the movement while keeping the phone in your hand." }
        return switch run.phase {
        case .ready: "Three confirmed landings unlock the next trick."
        case .armed: "Same detector as Play. Throw the \(node.trickID.displayName)."
        case .motion: "Catch it and hold still."
        case .settling: "Keep it steady."
        case .result: "Compare against the target."
        case .unknown: "Saved for review — nothing is guessed."
        case .failed: "Reconnect motion access, then try again."
        }
    }

}
