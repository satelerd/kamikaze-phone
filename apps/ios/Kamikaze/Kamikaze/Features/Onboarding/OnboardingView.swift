import KamikazeMotionCore
import SwiftUI

/// First-run onboarding is a playable origin story, not a carousel. It keeps
/// the existing product thesis and safety tone, then proves the sensor loop
/// with the original 2014 challenge before teaching one real trick.
struct OnboardingView: View {
    let onComplete: () -> Void

    private let shuvitFrames: [ReplayFrame]
    private let flipFrames: [ReplayFrame]

    @State private var step = OnboardingStep.board
    @State private var maxReachedStep = OnboardingStep.board
    @State private var run = NativeRunModel()
    @State private var targetReplay: ReplayController
    @State private var flipReplay: ReplayController
    @State private var resultReplay: ReplayController?
    @State private var lastFreefall: FreefallWindow?
    @State private var lastHeightM: Double?
    @State private var airPassed = false
    @State private var shuvitPassed = false
    @State private var flipPassed = false
    @State private var airAttempts = 0
    @State private var shuvitAttempts = 0
    @State private var flipAttempts = 0
    @State private var celebrationVisible = false

    @Environment(FeedbackCoordinator.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let catalog = TrickCatalog.provisional(gripHand: .right)
        let shuvitDefinition = catalog.definitions
            .first { $0.id == OnboardingChallengeEvaluator.firstShuvit }
        let frames = shuvitDefinition.map { TargetMotionGenerator.frames(for: $0) } ?? []
        shuvitFrames = frames
        _targetReplay = State(initialValue: ReplayController(frames: frames))
        let flipDefinition = catalog.definitions
            .first { $0.id == OnboardingChallengeEvaluator.firstFlip }
        let flipTarget = flipDefinition.map { TargetMotionGenerator.frames(for: $0) } ?? []
        flipFrames = flipTarget
        _flipReplay = State(initialValue: ReplayController(frames: flipTarget))
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

            if celebrationVisible {
                OnboardingConfettiBurst()
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
        .onChange(of: flipReplay.state) { _, state in
            guard state == .ended, step == .flipLearn else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                guard step == .flipLearn, flipReplay.state == .ended else { return }
                flipReplay.seek(toProgress: 0)
                flipReplay.play()
            }
        }
        .onDisappear {
            run.stop()
            targetReplay.pause()
            flipReplay.pause()
            resultReplay?.pause()
            feedback.evidenceWindowActive = false
        }
    }

    private var progressTape: some View {
        // Each capsule is a tap target back to any step already reached —
        // never a shortcut past maxReachedStep.
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? accent : .white.opacity(0.16))
                    .frame(height: item == step ? 5 : 3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard item.rawValue <= maxReachedStep.rawValue, item != step else { return }
                        move(to: item)
                    }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Onboarding step \(step.position) of \(OnboardingStep.allCases.count)")
        .accessibilityHint("Tap a previous segment to revisit that step")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .board:
            staticPage(
                eyebrow: "KAMIKAZE · PHONE FLIP",
                title: "YOUR PHONE\nIS THE BOARD.",
                body: "Throw. Rotate. Catch.",
                symbol: "iphone.gen3.radiowaves.left.and.right"
            )
        case .safety:
            staticPage(
                eyebrow: "BEFORE YOU THROW",
                title: "THROW\nSMART.",
                body: "Use a case. Start over something soft.",
                symbol: "shield.lefthalf.filled"
            )
        case .origin:
            originPage
        case .howToPlay:
            howToPlayPage
        case .straightAir:
            straightAirPage
        case .shuvitLearn:
            shuvitLearnPage
        case .shuvitTry:
            shuvitTryPage
        case .flipLearn:
            flipLearnPage
        case .flipTry:
            flipTryPage
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
        VStack(alignment: .leading, spacing: 20) {
            Text("WHERE IT STARTED")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.ion)

            Text("2014")
                .font(.system(size: 84, weight: .black, design: .rounded))
                .tracking(-5)

            Text("KAMIKAZE\nSTARTED HERE.")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .tracking(-2.2)

            Text("Throw your phone as high as you could. Height became your score — and you could compete with other players.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(KamikazeTheme.muted)
                .lineSpacing(5)

            Rectangle()
                .fill(KamikazeTheme.frost.opacity(0.16))
                .frame(height: 1)
                .padding(.vertical, 4)

            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text("NOW")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
                Text("LET'S TRY THE ORIGINAL.")
                    .font(.system(size: 23, weight: .black, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var howToPlayPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            challengeHeader(
                eyebrow: "HOW TO PLAY",
                title: "THREE MOVES.\nTHAT'S IT.",
                detail: "Start the detector before every throw."
            )

            VStack(spacing: 10) {
                instructionRow(
                    number: "1",
                    title: "PRESS START",
                    detail: "Tell Kamikaze you are ready.",
                    symbol: "hand.tap.fill"
                )
                instructionRow(
                    number: "2",
                    title: "THROW + CATCH",
                    detail: "The phone measures the entire movement.",
                    symbol: "arrow.up.and.down"
                )
                instructionRow(
                    number: "3",
                    title: "HOLD STILL",
                    detail: "Wait for the score to appear.",
                    symbol: "scope"
                )
            }

            Text("START → THROW → HOLD STILL → SCORE")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.volt)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func instructionRow(
        number: String,
        title: String,
        detail: String,
        symbol: String
    ) -> some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 24) {
            HStack(spacing: 14) {
                Text(number)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(KamikazeTheme.volt, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                    Text(detail)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                }

                Spacer(minLength: 4)

                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(KamikazeTheme.ion)
                    .frame(width: 30)
            }
            .padding(14)
        }
    }

    private var minimumAirLabel: String {
        "\(Int((OnboardingChallengeEvaluator.minimumStraightAirHeightM * 100).rounded())) CM"
    }

    private var straightAirPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            challengeHeader(
                eyebrow: "ORIGINAL MODE",
                title: "THROW YOUR PHONE\n\(minimumAirLabel)."
            )

            throwLoopGuide

            challengeStage(kind: .straightAir)

            if let lastHeightM {
                GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("YOUR HEIGHT")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                        Spacer()
                        Text("\(Int((lastHeightM * 100).rounded())) CM")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(accent)
                    }
                    .padding(15)
                }
            }

            statusBlock(title: straightAirStatus.title, detail: straightAirStatus.detail)

            Text("HEIGHT ESTIMATED FROM AIR TIME")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
        }
    }

    private var shuvitLearnPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            challengeHeader(
                eyebrow: "NOW LET'S PLAY FOR REAL",
                title: "LEARN A\nSHUVIT.",
                detail: "Rotate the phone 180°. Keep the screen facing up. Either direction counts."
            )

            ZStack(alignment: .topLeading) {
                ReplayPhoneScene(
                    controller: targetReplay,
                    accent: KamikazeTheme.volt,
                    appearanceOverride: .demo,
                    screenLabel: "TARGET"
                )
                stageBadge("3D PREVIEW · SHUVIT", color: KamikazeTheme.volt)
            }
            .frame(height: 340)
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            replayTransport(for: targetReplay, name: "Shuvit", tint: KamikazeTheme.volt)

        }
    }

    private var shuvitTryPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            challengeHeader(
                eyebrow: "TRICK 01 · YOUR TURN",
                title: "LAND A SHUVIT.",
                detail: "Frontside or backside. Both count."
            )

            throwLoopGuide

            challengeStage(kind: .shuvit)

            RunTelemetryHUD(run: run, leadingTitle: "TARGET", leadingValue: "180°")

            statusBlock(title: shuvitStatus.title, detail: shuvitStatus.detail)
        }
    }

    private var flipLearnPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            challengeHeader(
                eyebrow: "SHUVIT CLEARED · TRICK 02",
                title: "NICE. NOW\nLEARN A FLIP.",
                detail: "One full turn over the long edge. Either direction counts."
            )

            ZStack(alignment: .topLeading) {
                ReplayPhoneScene(
                    controller: flipReplay,
                    accent: KamikazeTheme.ion,
                    appearanceOverride: .demo,
                    screenLabel: "TARGET"
                )
                stageBadge("3D PREVIEW · FLIP", color: KamikazeTheme.ion)
            }
            .frame(height: 340)
            .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            replayTransport(for: flipReplay, name: "Flip", tint: KamikazeTheme.ion)

        }
    }

    private var flipTryPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            challengeHeader(
                eyebrow: "TRICK 02 · YOUR TURN",
                title: "LAND A FLIP.",
                detail: "Flip or reverse flip. Both count."
            )

            throwLoopGuide

            challengeStage(kind: .flip)

            RunTelemetryHUD(run: run, leadingTitle: "TARGET", leadingValue: "360°")

            statusBlock(title: flipStatus.title, detail: flipStatus.detail)
        }
    }

    private enum ChallengeStageKind {
        case straightAir
        case shuvit
        case flip
    }

    private func challengeStage(kind: ChallengeStageKind) -> some View {
        let targetFrames: [ReplayFrame]? = switch kind {
        case .shuvit: shuvitFrames
        case .flip: flipFrames
        case .straightAir: nil
        }
        return ZStack(alignment: .topLeading) {
            if let resultReplay, run.result != nil {
                ReplayPhoneScene(
                    controller: resultReplay,
                    accent: currentChallengePassed ? KamikazeTheme.volt : KamikazeTheme.hazard,
                    targetFrames: targetFrames,
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

    private func replayTransport(
        for controller: ReplayController,
        name: String,
        tint: Color
    ) -> some View {
        GlassSurface(role: .transport, cornerRadius: 20) {
            HStack(spacing: 12) {
                Button {
                    controller.togglePlayback()
                } label: {
                    Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(controller.state == .playing ? "Pause \(name) preview" : "Play \(name) preview")

                Slider(
                    value: Binding(
                        get: { controller.progress },
                        set: { controller.seek(toProgress: $0) }
                    ),
                    in: 0 ... 1
                )
                .tint(tint)
                .accessibilityLabel("\(name) preview position")

                Text(controller.speed.label)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(tint)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 4)
        }
    }

    private func challengeHeader(
        eyebrow: String,
        title: String,
        detail: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(accent)
            Text(title)
                .font(.system(size: 37, weight: .black, design: .rounded))
                .tracking(-1.7)
            if let detail {
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
        }
    }

    /// The only interaction lesson a new player needs. It stays visible on
    /// each playable step and highlights the phase the app is currently in.
    private var throwLoopGuide: some View {
        HStack(spacing: 5) {
            throwLoopStep(number: "1", label: "START", phase: .start)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(KamikazeTheme.muted.opacity(0.6))
            throwLoopStep(number: "2", label: "THROW", phase: .throwPhone)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(KamikazeTheme.muted.opacity(0.6))
            throwLoopStep(number: "3", label: "RESULT", phase: .result)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("First press Start, then throw your phone, then check the result")
    }

    private func throwLoopStep(
        number: String,
        label: String,
        phase: ThrowLoopPhase
    ) -> some View {
        let selected = currentThrowLoopPhase == phase
        return HStack(spacing: 5) {
            Text(number)
                .foregroundStyle(selected ? .black : accent)
            Text(label)
                .foregroundStyle(selected ? .black : KamikazeTheme.frost)
        }
        .font(.system(size: 9, weight: .black, design: .monospaced))
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(
            selected ? accent : KamikazeTheme.frost.opacity(0.08),
            in: Capsule()
        )
    }

    private enum ThrowLoopPhase {
        case start
        case throwPhone
        case result
    }

    private var currentThrowLoopPhase: ThrowLoopPhase {
        if run.result != nil { return .result }
        return active ? .throwPhone : .start
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
            move(to: .howToPlay)
        case .howToPlay:
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
                move(to: .flipLearn)
            } else if active {
                cancelChallenge()
            } else {
                beginChallenge()
            }
        case .flipLearn:
            flipReplay.pause()
            move(to: .flipTry)
            beginChallenge()
        case .flipTry:
            if flipPassed {
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
        if newStep.rawValue > maxReachedStep.rawValue { maxReachedStep = newStep }
        withAnimation(.snappy) { step = newStep }
    }

    private func synchronize(with newStep: OnboardingStep) {
        switch newStep {
        case .straightAir:
            targetReplay.pause()
            flipReplay.pause()
            clearCompletedRunIfNeeded()
            run.start()
        case .shuvitLearn:
            clearCompletedRunIfNeeded()
            run.stop()
            flipReplay.pause()
            targetReplay.seek(toProgress: 0)
            targetReplay.setSpeed(.half)
            targetReplay.play()
        case .shuvitTry:
            targetReplay.pause()
            flipReplay.pause()
            clearCompletedRunIfNeeded()
            run.start()
        case .flipLearn:
            clearCompletedRunIfNeeded()
            run.stop()
            targetReplay.pause()
            flipReplay.seek(toProgress: 0)
            flipReplay.setSpeed(.half)
            flipReplay.play()
        case .flipTry:
            targetReplay.pause()
            flipReplay.pause()
            clearCompletedRunIfNeeded()
            run.start()
        case .board, .safety, .origin, .howToPlay:
            run.stop()
            targetReplay.pause()
            flipReplay.pause()
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
        } else if step == .flipTry {
            flipPassed = false
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
        case .flipTry:
            flipAttempts += 1
            success = OnboardingChallengeEvaluator.passesFlip(
                status: result.match.status,
                trickID: result.match.candidates.first?.definition.id
            )
            flipPassed = success
        case .board, .safety, .origin, .howToPlay, .shuvitLearn, .flipLearn:
            return
        }

        feedback.evidenceWindowActive = false
        feedback.play(success ? .landed(scoreBand: 1) : .missed)
        feedback.playDetectionSound(success: success)
        if success { celebrate() }
    }

    private func bypassChallenge() {
        switch step {
        case .straightAir:
            move(to: .shuvitLearn)
        case .shuvitTry:
            move(to: .flipLearn)
        default:
            finishOnboarding()
        }
    }

    private func finishOnboarding() {
        run.stop()
        targetReplay.pause()
        flipReplay.pause()
        resultReplay?.pause()
        feedback.evidenceWindowActive = false
        onComplete()
    }

    private var primaryActionTitle: String {
        switch step {
        case .board, .safety, .origin: "CONTINUE"
        case .howToPlay: "TRY THE ORIGINAL"
        case .straightAir:
            if airPassed { "NEXT: LEARN A TRICK" }
            else if active { "CANCEL" }
            else if run.result != nil { "TRY AGAIN" }
            else { "START" }
        case .shuvitLearn: "TRY THE SHUVIT"
        case .shuvitTry:
            if shuvitPassed { "NEXT: LEARN FLIP" }
            else if active { "CANCEL" }
            else if run.result != nil { "TRY AGAIN" }
            else { "START" }
        case .flipLearn: "TRY THE FLIP"
        case .flipTry:
            if flipPassed { "ENTER KAMIKAZE" }
            else if active { "CANCEL" }
            else if run.result != nil { "TRY AGAIN" }
            else { "START" }
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
        case .flipTry: flipAttempts >= 3 && !flipPassed
        case .board, .safety, .origin, .howToPlay, .shuvitLearn, .flipLearn: false
        }
    }

    private var currentChallengePassed: Bool {
        switch step {
        case .straightAir: airPassed
        case .shuvitTry: shuvitPassed
        case .flipTry: flipPassed
        case .board, .safety, .origin, .howToPlay, .shuvitLearn, .flipLearn: false
        }
    }

    private var stageBadgeText: String {
        if currentChallengePassed { return "CLEARED" }
        if run.result != nil { return "3 · RESULT" }
        return active ? "2 · THROW" : "LIVE"
    }

    private var straightAirStatus: (title: String, detail: String) {
        if airPassed {
            return ("CLEARED", "\(minimumAirLabel) or higher.")
        }
        if let lastHeightM {
            let centimeters = Int((lastHeightM * 100).rounded())
            return ("\(centimeters) CM", "Go a little higher.")
        }
        return switch run.phase {
        case .ready: ("PRESS START", "Then throw straight up.")
        case .armed: ("THROW NOW", "Catch it and hold still.")
        case .motion: ("AIRBORNE", "Catch it.")
        case .settling: ("HOLD STILL", "Almost done.")
        case .result, .unknown: ("CHECKING", "Reading your air time.")
        case let .failed(message): ("MOTION SENSOR NEEDED", message)
        }
    }

    private var shuvitStatus: (title: String, detail: String) {
        if shuvitPassed {
            return ("SHUVIT LANDED", "Either direction counts.")
        }
        if let result = run.result {
            if let detected = result.evaluation.identity.trickID {
                return ("THAT WAS \(detected.displayName)", "Try one clean half-turn.")
            }
            return ("NOT QUITE", "Keep the screen up through the half-turn.")
        }
        return switch run.phase {
        case .ready: ("PRESS START", "Then throw a half-turn.")
        case .armed: ("THROW NOW", "Frontside or backside.")
        case .motion: ("IN MOTION", "Catch it flat.")
        case .settling: ("HOLD STILL", "Almost done.")
        case .result: ("CHECKING", "Reading the rotation.")
        case .unknown: ("NOT QUITE", "Try a clean half-turn.")
        case let .failed(message): ("MOTION SENSOR NEEDED", message)
        }
    }

    private var flipStatus: (title: String, detail: String) {
        if flipPassed {
            return ("FLIP LANDED", "You are ready.")
        }
        if let result = run.result {
            if let detected = result.evaluation.identity.trickID {
                return ("THAT WAS \(detected.displayName)", "Try one clean full turn.")
            }
            return ("NOT QUITE", "Try one clean full turn.")
        }
        return switch run.phase {
        case .ready: ("PRESS START", "Then throw one full flip.")
        case .armed: ("THROW NOW", "Either direction.")
        case .motion: ("IN MOTION", "Catch it flat.")
        case .settling: ("HOLD STILL", "Almost done.")
        case .result: ("CHECKING", "Reading the rotation.")
        case .unknown: ("NOT QUITE", "Try one clean full turn.")
        case let .failed(message): ("MOTION SENSOR NEEDED", message)
        }
    }

    private var accent: Color {
        switch step {
        case .board, .origin: KamikazeTheme.ion
        case .howToPlay: KamikazeTheme.volt
        case .safety, .straightAir: KamikazeTheme.hazard
        case .shuvitLearn, .shuvitTry: KamikazeTheme.volt
        case .flipLearn, .flipTry: KamikazeTheme.ion
        }
    }

    private func celebrate() {
        guard !reduceMotion else { return }
        celebrationVisible = false
        Task { @MainActor in
            await Task.yield()
            celebrationVisible = true
            try? await Task.sleep(for: .milliseconds(1_350))
            withAnimation(.easeOut(duration: 0.2)) {
                celebrationVisible = false
            }
        }
    }
}

private struct OnboardingConfettiBurst: View {
    @State private var released = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0 ..< 28, id: \.self) { index in
                    OnboardingConfettiPiece(
                        index: index,
                        canvasSize: proxy.size,
                        released: released
                    )
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.25)) {
                    released = true
                }
            }
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingConfettiPiece: View {
    let index: Int
    let canvasSize: CGSize
    let released: Bool

    private static let colors: [Color] = [
        KamikazeTheme.volt,
        KamikazeTheme.ion,
        KamikazeTheme.hazard,
        KamikazeTheme.frost,
    ]

    private var angle: Double {
        Double(index) / 28 * Double.pi * 2
    }

    private var radius: Double {
        min(canvasSize.width, canvasSize.height)
            * (0.28 + Double(index % 4) * 0.035)
    }

    var body: some View {
        Capsule()
            .fill(Self.colors[index % Self.colors.count])
            .frame(width: index.isMultiple(of: 3) ? 12 : 7, height: 20)
            .rotationEffect(.degrees(released ? Double(index * 61) : Double(index * 17)))
            .position(x: canvasSize.width / 2, y: canvasSize.height * 0.44)
            .offset(
                x: released ? cos(angle) * radius : 0,
                y: released ? sin(angle) * radius + 90 : 0
            )
            .opacity(released ? 0 : 1)
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
