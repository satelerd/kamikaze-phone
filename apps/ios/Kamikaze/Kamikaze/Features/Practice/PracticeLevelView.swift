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

    init(node: PracticeTrickNode, pair: PracticePair) {
        self.node = node
        self.pair = pair
        _run = State(initialValue: NativeRunModel(expectedTrickID: node.trickID))
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
                HStack {
                    SectionKicker(text: kicker)
                    Spacer()
                    Button("ZERO POSE", systemImage: "scope") {
                        run.zeroPose()
                        feedback.play(.zeroed)
                    }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .adaptiveGlassButton()
                }

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

                GlassSurface(role: .stage, cornerRadius: 42) {
                    ZStack {
                        Circle().fill(accent.opacity(0.13)).overlay(Circle().stroke(.white.opacity(0.13))).padding(10)
                        LivePhoneScene(attitude: run.relativeAttitude, accent: accent)
                    }
                }
                .frame(maxHeight: 380)

                GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
                    HStack(spacing: 18) {
                        metric("REPS", "\(min(reps, PracticeProgress.repsToUnlock))/\(PracticeProgress.repsToUnlock)")
                        metric("MOTION", sensorLabel)
                        metric("RATE", run.measuredHz > 0 ? "\(Int(run.measuredHz.rounded())) HZ" : "— HZ")
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
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
            await progressModel.refresh()
        }
        .onDisappear {
            run.stop()
            experience.report(phase: .idle)
        }
        .onChange(of: run.phase) { _, phase in
            experience.report(phase: phase.experiencePhase)
            reactToPhase(phase)
        }
        .onChange(of: run.gyroDps) { _, gyroDps in
            experience.reportMotion(gyroDps: gyroDps)
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
        case .unknown:
            feedback.evidenceWindowActive = false
            feedback.play(.needsReview)
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

    private var kicker: String {
        let base = String(format: "PRACTICE %02d", pair.order)
        switch run.phase {
        case .ready: return "\(base) / READY"
        case .armed: return "\(base) / ARMED"
        case .motion: return "\(base) / MOTION"
        case .settling: return "\(base) / LANDING"
        case .result: return "\(base) / LANDED"
        case .unknown: return "\(base) / REVIEW"
        case .failed: return "\(base) / SENSOR"
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

    private var sensorLabel: String {
        if case .failed = run.phase { return "ERROR" }
        return run.measuredHz > 0 ? "LIVE" : "WAITING"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.muted)
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.frost)
        }
        .frame(maxWidth: .infinity)
    }
}
