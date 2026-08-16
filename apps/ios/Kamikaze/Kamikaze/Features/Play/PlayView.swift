import KamikazeMotionCore
import SwiftUI

struct PlayView: View {
    @State private var run = NativeRunModel()
    @State private var playMode = PlayMode.free
    @State private var followPrompt = FollowPromptDeck.first
    @State private var followQueue = FollowPromptDeck.shuffled(avoiding: FollowPromptDeck.first)
    @Namespace private var glassNamespace
    @Environment(ExperienceCoordinator.self) private var experience
    @Environment(FeedbackCoordinator.self) private var feedback
    @AppStorage(BetaFlags.followMode) private var followModeEnabled = false
    @AppStorage(BetaFlags.classicMode) private var classicModeEnabled = false

    private var active: Bool {
        switch run.phase {
        case .armed, .motion, .settling: true
        case .ready, .result, .unknown, .failed: false
        }
    }

    var body: some View {
        ZStack {
            if run.result == nil {
                ExperienceFieldBackground()
                GlassCluster(spacing: 14) {
                    playContent
                }
            } else {
                // A full-screen result owns its own RealityView and Metal
                // field. Removing (rather than merely hiding) Play's stage
                // prevents two 3D scenes and two full-screen shaders from
                // rendering at the same time underneath the cover.
                KamikazeTheme.pitch.ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { run.start() }
        .onDisappear {
            run.stop()
            experience.report(phase: .idle)
        }
        .onChange(of: run.phase) { _, phase in
            experience.report(phase: phase.experiencePhase)
            reactToPhase(phase)
        }
        .onChange(of: followModeEnabled) { _, enabled in
            if !enabled, playMode == .follow { playMode = .free }
        }
        .onChange(of: classicModeEnabled) { _, enabled in
            if !enabled, playMode == .classic { playMode = .free }
        }
        .fullScreenCover(item: Binding(
            get: { run.result },
            set: { if $0 == nil { run.dismissResult() } }
        )) { result in
            switch playMode {
            case .free:
                ResultReplayView(
                    result: result,
                    onAgain: run.dismissResultAndRearm,
                    onClose: run.dismissResult,
                    onReview: run.applyHumanReview
                )
            case .follow:
                ResultReplayView(
                    result: result,
                    primaryTitle: "NEXT CALL",
                    practiceTarget: followPrompt.trickID,
                    onAgain: {
                        advanceFollowPrompt()
                        run.dismissResultAndRearm()
                    },
                    onClose: run.dismissResult,
                    onReview: run.applyHumanReview,
                    reviewContextNote: followPrompt.evidenceNote,
                    requiresReviewBeforeAgain: true
                )
            case .classic:
                ClassicResultView(
                    result: result,
                    onAgain: run.dismissResultAndRearm,
                    onClose: run.dismissResult
                )
            }
        }
    }

    private var playContent: some View {
        VStack(spacing: 16) {
                // Same typographic voice as Setup's header. The phase story
                // moved into the button and the HUD — no status subtitle.
                Text(screenTitle)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .tracking(-1.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if availableModes.count > 1 {
                    modeSelector
                }

                if playMode == .follow {
                    followCallCard
                } else if playMode == .classic {
                    classicBrief
                }

                // The phone floats directly over the field — no stage boxes.
                LiveRunStage(run: run, accent: accent, initialZoom: 0.33)
                    .frame(maxHeight: 520)

                RunTelemetryHUD(run: run)

                if case let .failed(message) = run.phase {
                    Text(message)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(KamikazeTheme.hazard)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                Button {
                    if active {
                        run.cancel()
                        feedback.play(.cancelled)
                    } else {
                        run.arm()
                    }
                } label: {
                    Text(active ? "CANCEL" : primaryActionTitle)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 84)
                }
                .adaptiveGlassButton(prominent: true, tint: active ? KamikazeTheme.hazard : KamikazeTheme.ion)
                // Stable identity: arming morphs the same surface instead of
                // replacing the button.
                .kamikazeGlassID("play-primary-action", in: glassNamespace)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var availableModes: [PlayMode] {
        var modes: [PlayMode] = [.free]
        if followModeEnabled { modes.append(.follow) }
        if classicModeEnabled { modes.append(.classic) }
        return modes
    }

    private var screenTitle: String {
        switch playMode {
        case .free: "KAMIKAZE\nPHONE FLIP"
        case .follow: "FOLLOW\nTHE CALL"
        case .classic: "KAMIKAZE\nCLASSIC"
        }
    }

    private var primaryActionTitle: String {
        switch playMode {
        case .free: "THROW"
        case .follow: "START FOLLOW"
        case .classic: "START CLASSIC"
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 8) {
            ForEach(availableModes) { mode in
                Button(mode.title) {
                    guard !active else { return }
                    playMode = mode
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    (playMode == mode ? KamikazeTheme.volt : .white.opacity(0.07)),
                    in: Capsule()
                )
                .foregroundStyle(playMode == mode ? Color.black : KamikazeTheme.frost)
                .overlay(Capsule().stroke(.white.opacity(playMode == mode ? 0.35 : 0.1)))
                .buttonStyle(.plain)
                .disabled(active)
            }
        }
    }

    private var followCallCard: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("THE CALL")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.volt)
                    Spacer()
                    Button("NEW CALL", systemImage: "shuffle") { advanceFollowPrompt() }
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .disabled(active)
                }
                Text(followPrompt.trickID.displayName)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .tracking(-0.8)
                Text(followPrompt.condition.title)
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.hazard)
                Text(followPrompt.condition.instruction)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                Text("Capture ends automatically. Review the replay, then tap LANDED IT or MISSED before the next call.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .padding(16)
        }
    }

    private var classicBrief: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("HOW HIGH CAN IT GO?")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Text("Throw and catch. Rotation does not add points — Classic reports measured air time and estimated peak height only.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .padding(16)
        }
    }

    private func advanceFollowPrompt() {
        if followQueue.isEmpty {
            followQueue = FollowPromptDeck.shuffled(avoiding: followPrompt)
        }
        guard !followQueue.isEmpty else { return }
        followPrompt = followQueue.removeFirst()
    }

    private var accent: Color {
        switch run.phase {
        case .motion, .settling: KamikazeTheme.hazard
        case .result: KamikazeTheme.volt
        case .unknown, .failed: KamikazeTheme.hazard
        case .ready, .armed: KamikazeTheme.ion
        }
    }

    /// Cue ordering matters: the armed tick fires BEFORE the evidence window
    /// opens; catch/result cues fire only after the capture has closed.
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

}
