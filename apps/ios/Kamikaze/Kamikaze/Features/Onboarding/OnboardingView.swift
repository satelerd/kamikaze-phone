import KamikazeMotionCore
import SwiftUI

/// First-run onboarding is a playable origin story, not a carousel. It keeps
/// the existing product thesis and safety tone, then proves the sensor loop
/// with the original 2014 challenge before teaching one real trick.
struct OnboardingView: View {
    let onComplete: () -> Void

    private let shuvitFrames: [ReplayFrame]

    @State private var step = OnboardingStep.board
    @State private var run = NativeRunModel()
    @State private var targetReplay: ReplayController
    @State private var resultReplay: ReplayController?
    @State private var lastFreefall: FreefallWindow?
    @State private var lastHeightM: Double?
    @State private var airPassed = false
    @State private var shuvitPassed = false
    @State private var airAttempts = 0
    @State private var shuvitAttempts = 0

    @Environment(FeedbackCoordinator.self) private var feedback

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let definition = TrickCatalog.provisional(gripHand: .right)
            .definitions.first { $0.id == OnboardingChallengeEvaluator.firstShuvit }
        let frames = definition.map { TargetMotionGenerator.frames(for: $0) } ?? []
        shuvitFrames = frames
        _targetReplay = State(initialValue: ReplayController(frames: frames))
    }

    var body: some View {
        ZStack {
            KineticBackground(accent: accent)

            VStack(spacing: 0) {
                progressTape
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                ScrollView {
                    stepContent
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                        .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)

                actionArea
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
            }
        }
        .animation(.snappy, value: step)
        .animation(.snappy, value: airPassed)
        .animation(.snappy, value: shuvitPassed)
        .onAppear {
            PhoneModelLibrary.shared.preload()
            synchronize(with: step)
        }
        .onChange(of: step) { _, newStep in synchronize(with: newStep) }
        .onChange(of: run.phase) { _, phase in
            feedback.evidenceWindowActive = phase.isCapturingEvidence
        }
        .onChange(of: run.result?.id) { _, resultID in
            guard resultID != nil, let result = run.result else { return }
            resolve(result)
        }
        .onChange(of: targetReplay.state) { _, state in
            guard state == .ended, step == .shuvitLearn else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                guard step == .shuvitLearn, targetReplay.state == .ended else { return }
                targetReplay.seek(toProgress: 0)
                targetReplay.play()
            }
        }
        .onDisappear {
            run.stop()
            targetReplay.pause()
            resultReplay?.pause()
            feedback.evidenceWindowActive = false
        }
    }

    private var progressTape: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? accent : .white.opacity(0.16))
                    .frame(height: item == step ? 5 : 3)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Onboarding step \(step.position) of \(OnboardingStep.allCases.count)")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .board:
            staticPage(
                eyebrow: "WELCOME TO KAMIKAZE",
                title: "YOUR PHONE\nIS THE BOARD.",
                body: "Throw it. Rotate it. Catch it. Kamikaze reads the motion, identifies the trick and rebuilds the throw in 3D.",
                symbol: "iphone.gen3.radiowaves.left.and.right"
            )
        case .safety:
            staticPage(
                eyebrow: "BEFORE YOU THROW",
                title: "CHOOSE YOUR\nLEVEL OF CHAOS.",
                body: "A case and a soft landing zone are smart. Going case-free is extremely Kamikaze—and entirely your call.",
                symbol: "shield.lefthalf.filled"
            )
        case .origin:
            originPage
        case .straightAir:
            straightAirPage
        case .shuvitLearn:
            shuvitLearnPage
        case .shuvitTry:
            shuvitTryPage
        }
    }

    private func staticPage(
        eyebrow: String,
        title: String,
        body: String,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(accent)

            GlassSurface(role: .stage, cornerRadius: 48) {
                Image(systemName: symbol)
                    .font(.system(size: 66, weight: .light))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, minHeight: 238)
            }

            Text(title)
                .font(.system(size: 43, weight: .black, design: .rounded))
                .tracking(-2)
                .foregroundStyle(KamikazeTheme.frost)

            Text(body)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(KamikazeTheme.muted)
                .lineSpacing(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var originPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("WHERE IT STARTED")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.ion)

            HStack(alignment: .firstTextBaseline) {
                Text("2014")
                    .font(.system(size: 82, weight: .black, design: .rounded))
                    .tracking(-5)
                Spacer()
                Text("V1")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.ion)
            }

            Text("ONE THROW.\nONE NUMBER.")
                .font(.system(size: 39, weight: .black, design: .rounded))
                .tracking(-1.8)

            GlassSurface(role: .instrumentHUD, cornerRadius: 24) {
                HStack(spacing: 16) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 42, weight: .black))
                        .foregroundStyle(KamikazeTheme.hazard)
                        .frame(width: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("THE ORIGINAL KAMIKAZE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                        Text("Throw your phone straight up. The higher it went, the higher your score.")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }

            Text("NOW THE PHONE CAN READ THE TRICK.")
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(KamikazeTheme.volt)
            Text("We brought the original challenge back, then added real motion capture, trick detection, scoring, Practice and interactive 3D replay.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(KamikazeTheme.muted)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var minimumAirLabel: String {
        "\(Int((OnboardingChallengeEvaluator.minimumStraightAirHeightM * 100).rounded())) CM"
    }

    private var straightAirPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            challengeHeader(
                eyebrow: "THE 2014 TEST",
                title: "GET SOME AIR.",
                detail: "Throw it straight up and catch it. Rotation does not matter yet."
            )

            challengeStage(kind: .straightAir)

            HStack(spacing: 10) {
                metricCard(
                    value: lastHeightM.map { "\(Int(($0 * 100).rounded())) CM" } ?? "— CM",
                    label: "ESTIMATED"
                )
                metricCard(value: minimumAirLabel, label: "MINIMUM")
            }

            statusBlock(title: straightAirStatus.title, detail: straightAirStatus.detail)

            Text("Height is estimated from measured air time using h = g·T²/8. The phone does not directly observe absolute vertical position.")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
                .lineSpacing(3)
        }
    }

    private var shuvitLearnPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            challengeHeader(
                eyebrow: "YOUR FIRST TRICK · LEARN",
                title: "ADD A SHUVIT.",
                detail: "Half spin around the screen axis. Keep the screen facing up."
            )

            ZStack(alignment: .topLeading) {
                ReplayPhoneScene(
                    controller: targetReplay,
                    accent: KamikazeTheme.volt,
                    appearanceOverride: .demo,
                    screenLabel: "TARGET"
                )
                stageBadge("TARGET · SHUVIT", color: KamikazeTheme.volt)
            }
            .frame(height: 340)
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            replayTransport

            GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "rotate.3d")
                        .font(.system(size: 25, weight: .black))
                        .foregroundStyle(KamikazeTheme.ion)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WATCH THE DIRECTION")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                        Text("Play it slowly, scrub the timeline, then drag the stage to inspect the axis.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(15)
            }
        }
    }

    private var shuvitTryPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            challengeHeader(
                eyebrow: "YOUR FIRST TRICK · TRY",
                title: "LAND THE SHUVIT.",
                detail: "Only the exact half-spin target clears the tutorial."
            )

            challengeStage(kind: .shuvit)

            RunTelemetryHUD(run: run, leadingTitle: "TARGET", leadingValue: "180°")

            statusBlock(title: shuvitStatus.title, detail: shuvitStatus.detail)
        }
    }

    private enum ChallengeStageKind {
        case straightAir
        case shuvit
    }

    private func challengeStage(kind: ChallengeStageKind) -> some View {
        ZStack(alignment: .topLeading) {
            if let resultReplay, run.result != nil {
                ReplayPhoneScene(
                    controller: resultReplay,
                    accent: currentChallengePassed ? KamikazeTheme.volt : KamikazeTheme.hazard,
                    targetFrames: kind == .shuvit ? shuvitFrames : nil,
                    arcWindow: kind == .straightAir ? lastFreefall : nil
                )
            } else {
                LiveRunStage(run: run, accent: accent, initialZoom: 0.55)
            }
            stageBadge(stageBadgeText, color: currentChallengePassed ? KamikazeTheme.volt : accent)
        }
        .frame(height: 330)
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var replayTransport: some View {
        GlassSurface(role: .transport, cornerRadius: 20) {
            HStack(spacing: 12) {
                Button {
                    targetReplay.togglePlayback()
                } label: {
                    Image(systemName: targetReplay.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(KamikazeTheme.volt)
                        .frame(width: 38, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(targetReplay.state == .playing ? "Pause Shuvit preview" : "Play Shuvit preview")

                Slider(
                    value: Binding(
                        get: { targetReplay.progress },
                        set: { targetReplay.seek(toProgress: $0) }
                    ),
                    in: 0 ... 1
                )
                .tint(KamikazeTheme.volt)
                .accessibilityLabel("Shuvit preview position")

                Text(targetReplay.speed.label)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
        }
    }

    private func challengeHeader(eyebrow: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
            Text(title)
                .font(.system(size: 37, weight: .black, design: .rounded))
                .tracking(-1.7)
            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(KamikazeTheme.muted)
        }
    }

    private func metricCard(value: String, label: String) -> some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(value == minimumAirLabel ? KamikazeTheme.frost : accent)
                Text(label)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
    }

    private func statusBlock(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(currentChallengePassed ? KamikazeTheme.volt : KamikazeTheme.frost)
            Text(detail)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(KamikazeTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stageBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color, in: Capsule())
            .padding(12)
            .allowsHitTesting(false)
    }

    private var actionArea: some View {
        VStack(spacing: 7) {
            Button(action: primaryAction) {
                Text(primaryActionTitle)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .adaptiveGlassButton(prominent: true, tint: primaryTint)
            .accessibilityIdentifier("onboarding-primary-action")

            if currentChallengePassed, step.isSensorChallenge {
                Button("TRY AGAIN") { beginChallenge() }
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                    .frame(minHeight: 28)
                    .buttonStyle(.plain)
            } else if canBypassChallenge {
                Button("CONTINUE WITHOUT SENSOR") { bypassChallenge() }
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                    .frame(minHeight: 28)
                    .buttonStyle(.plain)
            } else if canDeferTraining {
                Button("TRAIN THIS LATER") { bypassChallenge() }
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                    .frame(minHeight: 28)
                    .buttonStyle(.plain)
            }
        }
    }

    private func primaryAction() {
        switch step {
        case .board:
            move(to: .safety)
        case .safety:
            move(to: .origin)
        case .origin:
            move(to: .straightAir)
        case .straightAir:
            if airPassed {
                move(to: .shuvitLearn)
            } else if active {
                cancelChallenge()
            } else {
                beginChallenge()
            }
        case .shuvitLearn:
            targetReplay.pause()
            move(to: .shuvitTry)
            beginChallenge()
        case .shuvitTry:
            if shuvitPassed {
                finishOnboarding()
            } else if active {
                cancelChallenge()
            } else {
                beginChallenge()
            }
        }
    }

    private func move(to newStep: OnboardingStep) {
        resultReplay?.pause()
        resultReplay = nil
        withAnimation(.snappy) { step = newStep }
    }

    private func synchronize(with newStep: OnboardingStep) {
        switch newStep {
        case .straightAir:
            targetReplay.pause()
            clearCompletedRunIfNeeded()
            run.start()
        case .shuvitLearn:
            clearCompletedRunIfNeeded()
            run.stop()
            targetReplay.seek(toProgress: 0)
            targetReplay.setSpeed(.half)
            targetReplay.play()
        case .shuvitTry:
            targetReplay.pause()
            clearCompletedRunIfNeeded()
            run.start()
        case .board, .safety, .origin:
            run.stop()
            targetReplay.pause()
        }
    }

    private func clearCompletedRunIfNeeded() {
        guard run.result != nil else { return }
        run.dismissResult()
    }

    private func beginChallenge() {
        resultReplay?.pause()
        resultReplay = nil
        if step == .straightAir {
            airPassed = false
            lastHeightM = nil
            lastFreefall = nil
        } else if step == .shuvitTry {
            shuvitPassed = false
        }
        feedback.play(.armed)
        if run.result != nil {
            run.dismissResultAndRearm()
        } else {
            run.arm()
        }
    }

    private func cancelChallenge() {
        run.cancel()
        feedback.evidenceWindowActive = false
        feedback.play(.cancelled)
    }

    private func resolve(_ result: NativeRunResult) {
        let frames = ReplayBuilder.normalized(ReplayBuilder.buildFrames(
            payload: result.capture.samplePayload,
            boundaries: result.capture.attempt.boundaries
        ))
        let replay = ReplayController(frames: frames)
        resultReplay = replay
        replay.setSpeed(.half)
        replay.play()

        let success: Bool
        switch step {
        case .straightAir:
            airAttempts += 1
            let freefall = ReplayBuilder.freefallWindow(in: frames)
            lastFreefall = freefall
            lastHeightM = freefall?.peakHeightM
            success = OnboardingChallengeEvaluator.passesStraightAir(
                estimatedHeightM: lastHeightM
            )
            airPassed = success
        case .shuvitTry:
            shuvitAttempts += 1
            success = OnboardingChallengeEvaluator.passesShuvit(
                status: result.match.status,
                trickID: result.match.candidates.first?.definition.id
            )
            shuvitPassed = success
        case .board, .safety, .origin, .shuvitLearn:
            return
        }

        feedback.evidenceWindowActive = false
        feedback.play(success ? .landed(scoreBand: 1) : .missed)
        feedback.playDetectionSound(success: success)
    }

    private func bypassChallenge() {
        if step == .straightAir {
            move(to: .shuvitLearn)
        } else {
            finishOnboarding()
        }
    }

    private func finishOnboarding() {
        run.stop()
        targetReplay.pause()
        resultReplay?.pause()
        feedback.evidenceWindowActive = false
        onComplete()
    }

    private var primaryActionTitle: String {
        switch step {
        case .board, .safety: "CONTINUE"
        case .origin: "TRY THE ORIGINAL"
        case .straightAir:
            if airPassed { "NEXT: LEARN SHUVIT" }
            else if active { "CANCEL THROW" }
            else if run.result != nil { "TRY STRAIGHT AIR AGAIN" }
            else { "START STRAIGHT AIR" }
        case .shuvitLearn: "TRY THE SHUVIT"
        case .shuvitTry:
            if shuvitPassed { "ENTER KAMIKAZE" }
            else if active { "CANCEL THROW" }
            else if run.result != nil { "TRY SHUVIT AGAIN" }
            else { "START SHUVIT" }
        }
    }

    private var primaryTint: Color {
        if active { return KamikazeTheme.hazard }
        if currentChallengePassed { return KamikazeTheme.volt }
        return accent
    }

    private var active: Bool {
        run.phase.isCapturingEvidence
    }

    private var sensorFailed: Bool {
        if case .failed = run.phase { return true }
        return false
    }

    private var canBypassChallenge: Bool {
        step.isSensorChallenge && sensorFailed
    }

    private var canDeferTraining: Bool {
        switch step {
        case .straightAir: airAttempts >= 3 && !airPassed
        case .shuvitTry: shuvitAttempts >= 3 && !shuvitPassed
        case .board, .safety, .origin, .shuvitLearn: false
        }
    }

    private var currentChallengePassed: Bool {
        switch step {
        case .straightAir: airPassed
        case .shuvitTry: shuvitPassed
        case .board, .safety, .origin, .shuvitLearn: false
        }
    }

    private var stageBadgeText: String {
        if currentChallengePassed { return "CLEARED" }
        if run.result != nil { return "REPLAY · YOU" }
        return active ? "CAPTURING" : "LIVE · LEVEL FIRST"
    }

    private var straightAirStatus: (title: String, detail: String) {
        if airPassed {
            return ("AIR CLEARED", "You passed \(minimumAirLabel.lowercased()). Now turn that air into a trick.")
        }
        if let lastHeightM {
            let centimeters = Int((lastHeightM * 100).rounded())
            return ("\(centimeters) CM — GO HIGHER", "Keep the phone level and give it a little more air.")
        }
        return switch run.phase {
        case .ready: ("READY?", "Level the phone, start the test, then throw straight up.")
        case .armed: ("THROW WHEN READY", "Catch it and hold still.")
        case .motion: ("AIRBORNE", "Eyes on the catch.")
        case .settling: ("HOLD THE CATCH", "Keep the phone still while the attempt closes.")
        case .result, .unknown: ("CHECKING HEIGHT", "Reading the measured air window.")
        case let .failed(message): ("MOTION SENSOR NEEDED", message)
        }
    }

    private var shuvitStatus: (title: String, detail: String) {
        if shuvitPassed {
            return ("SHUVIT LANDED", "You cleared the first trick. The rest of Kamikaze is open.")
        }
        if let result = run.result {
            if let detected = result.evaluation.identity.trickID {
                return ("THAT WAS \(detected.displayName)", "The target is BACKSIDE SHUVIT: one clean half-spin.")
            }
            return ("NOT THE TARGET YET", "Replay the preview, then keep the screen facing up through the half-spin.")
        }
        return switch run.phase {
        case .ready: ("READY TO TRY?", "Start, throw the half-spin and catch it flat.")
        case .armed: ("THROW THE SHUVIT", "Half-spin around the screen axis.")
        case .motion: ("TRICK IN MOTION", "Find the flat catch.")
        case .settling: ("HOLD THE CATCH", "Keep it steady.")
        case .result: ("CHECKING TARGET", "Comparing your throw with the Shuvit definition.")
        case .unknown: ("NOT THE TARGET", "No trick was guessed.")
        case let .failed(message): ("MOTION SENSOR NEEDED", message)
        }
    }

    private var accent: Color {
        switch step {
        case .board, .origin: KamikazeTheme.ion
        case .safety, .straightAir: KamikazeTheme.hazard
        case .shuvitLearn, .shuvitTry: KamikazeTheme.volt
        }
    }
}

private extension NativeRunPhase {
    var isCapturingEvidence: Bool {
        switch self {
        case .armed, .motion, .settling: true
        case .ready, .result, .unknown, .failed: false
        }
    }
}
