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
                // Same typographic voice as Setup's header. The phase story
                // moved into the button and the HUD — no status subtitle.
                Text("KAMIKAZE\nPHONE FLIP.")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .tracking(-1.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // The phone floats directly over the field — no stage boxes.
                LiveRunStage(run: run, accent: accent, initialZoom: 0.40)
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
                    Text(active ? "CANCEL" : "THROW")
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
