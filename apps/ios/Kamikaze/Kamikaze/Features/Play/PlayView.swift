import KamikazeMotionCore
import SwiftUI

struct PlayView: View {
    @State private var run = NativeRunModel()
    @Namespace private var glassNamespace
    @Environment(ExperienceCoordinator.self) private var experience
    @Environment(FeedbackCoordinator.self) private var feedback

    private var active: Bool {
        switch run.phase {
        case .armed, .motion, .settling: true
        case .ready, .result, .unknown, .failed: false
        }
    }

    var body: some View {
        ZStack {
            ExperienceFieldBackground()
            GlassCluster(spacing: 14) {
                playContent
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
        .fullScreenCover(item: Binding(
            get: { run.result },
            set: { if $0 == nil { run.dismissResult() } }
        )) { result in
            ResultReplayView(
                result: result,
                onAgain: run.dismissResultAndRearm,
                onClose: run.dismissResult,
                onReview: run.applyHumanReview
            )
        }
    }

    private var playContent: some View {
        VStack(spacing: 16) {
                Spacer(minLength: 8)

                // The phone floats directly over the field — no stage boxes.
                LiveRunStage(run: run, accent: accent, initialZoom: 0.5)
                    .frame(maxHeight: 480)

                RunTelemetryHUD(run: run)

                VStack(spacing: 6) {
                    Text(title).font(.system(size: 32, weight: .black, design: .rounded)).tracking(-1.2)
                    Text(detail).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(KamikazeTheme.muted)
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
                    Text(active ? "CANCEL SESSION" : "START SESSION")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 72)
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

    private var title: String {
        switch run.phase {
        case .ready: "READY TO FLIP?"
        case .armed: "THROW WHEN READY"
        case .motion: "TRICK IN MOTION"
        case .settling: "HOLD THE CATCH"
        case .result: "LANDED"
        case .unknown: "CHECK THE THROW"
        case let .failed(message): "SENSOR ERROR\n\(message)"
        }
    }

    private var detail: String {
        switch run.phase {
        case .ready: "A quick spin is enough. You do not need a high throw."
        case .armed: "The full 100 Hz stream is armed."
        case .motion: "Rotation captured — catch it and steady the phone."
        case .settling: "Keep it still for a fraction of a second."
        case .result: "Opening measured replay."
        case .unknown: "The evidence is saved for review, not guessed."
        case .failed: "Reconnect motion access, then try again."
        }
    }

}
