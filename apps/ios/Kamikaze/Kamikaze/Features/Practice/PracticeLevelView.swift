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
            ExperienceFieldBackground()
            VStack(spacing: 14) {
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

                RunTelemetryHUD(
                    run: run,
                    leadingTitle: "REPS",
                    leadingValue: "\(min(reps, PracticeProgress.repsToUnlock))/\(PracticeProgress.repsToUnlock)",
                    showsGyro: false
                )

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
                    if active {
                        run.cancel()
                        feedback.play(.cancelled)
                    } else {
                        run.arm()
                    }
                } label: {
                    Text(active ? "CANCEL" : "START PRACTICE")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 66)
                }
                .adaptiveGlassButton(prominent: true, tint: active ? KamikazeTheme.hazard : KamikazeTheme.ion)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            run.start()
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
            run.stop()
            experience.report(phase: .idle)
        }
        .onChange(of: run.phase) { _, phase in
            experience.report(phase: phase.experiencePhase)
            reactToPhase(phase)
        }
        .fullScreenCover(item: Binding(
            get: { run.result },
            set: { if $0 == nil { run.dismissResult() } }
        )) { result in
            ResultReplayView(
                result: result,
                primaryTitle: "TRY AGAIN",
                practiceTarget: node.trickID,
                onAgain: run.dismissResultAndRearm,
                onClose: run.dismissResult,
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

    private var reps: Int {
        progressModel.progress.qualifyingReps(for: node.trickID)
    }

    /// The target demo owns the stage only while the level is at rest; from
    /// ARMED onward the live pose is the hero.
    private var showsTarget: Bool {
        if case .ready = run.phase { return targetReplay.hasReplay }
        return false
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
        switch run.phase {
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
        switch run.phase {
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
