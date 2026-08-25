import KamikazeMotionCore
import SwiftUI

struct PlayView: View {
    @State private var run = NativeRunModel()
    @State private var playCamera = PlayCameraCaptureModel()
    @State private var playMode = PlayMode.free
    @State private var followPrompt = FollowPromptDeck.first
    @State private var followQueue = FollowPromptDeck.shuffled(avoiding: FollowPromptDeck.first)
    @State private var line = LineSessionState()
    @State private var lineRearmTask: Task<Void, Never>?
    @State private var showsCameraRun = false
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
            if run.result == nil || playMode == .line || playMode == .camera {
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
            lineRearmTask?.cancel()
            run.stop()
            experience.report(phase: .idle)
            Task { await playCamera.shutdown() }
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
        .navigationDestination(isPresented: $showsCameraRun) {
            CameraRunPrototypeView()
        }
        .fullScreenCover(item: Binding(
            get: {
                switch playMode {
                case .free, .follow, .classic: run.result
                case .line, .camera: nil
                }
            },
            set: { if $0 == nil { run.dismissResult() } }
        )) { result in
            switch playMode {
            case .free:
                ResultReplayView(
                    result: result,
                    onAgain: rearmAfterCameraTake,
                    onClose: run.dismissResult,
                    onReview: run.applyHumanReview,
                    cameraCapture: playCamera
                )
            case .follow:
                ResultReplayView(
                    result: result,
                    primaryTitle: "NEXT CALL",
                    practiceTarget: followPrompt.trickID,
                    onAgain: {
                        Task { @MainActor in
                            await playCamera.waitUntilAttemptIsSealed()
                            advanceFollowPrompt()
                            run.dismissResultAndRearm()
                        }
                    },
                    onClose: run.dismissResult,
                    onReview: run.applyHumanReview,
                    reviewContextNote: followPrompt.evidenceNote,
                    requiresReviewBeforeAgain: true,
                    cameraCapture: playCamera
                )
            case .classic:
                ClassicResultView(
                    result: result,
                    onAgain: rearmAfterCameraTake,
                    onClose: run.dismissResult,
                    cameraCapture: playCamera
                )
            case .line, .camera:
                EmptyView()
            }
        }
    }

    private var playContent: some View {
        VStack(spacing: 16) {
                if playMode == .free {
                    // Free is the canonical game surface. The other modes own
                    // purpose-built instruments and do not repeat a masthead.
                    Text("KAMIKAZE\nPHONE FLIP")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(-1.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if availableModes.count > 1 {
                    modeSelector
                }

                if playMode != .camera {
                    cameraCaptureControl
                }

                if playMode == .line {
                    lineLatestCard
                    lineHistoryCard
                } else if playMode == .follow {
                    followCallCard
                } else if playMode == .classic {
                    classicBrief
                }

                if playMode != .camera {
                    // The phone floats directly over the field — no stage boxes.
                    LiveRunStage(
                        run: run,
                        accent: accent,
                        initialZoom: 0.33,
                        screenVideoMaterial: playCamera.isEnabled ? playCamera.screenVideoMaterial : nil
                    )
                        .frame(maxHeight: playMode == .line ? 245 : 560)
                }

                if case let .failed(message) = run.phase {
                    Text(message)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(KamikazeTheme.hazard)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if let cameraError = playCamera.errorMessage {
                    Text("CAMERA  /  \(cameraError)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.hazard)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if playMode != .camera {
                    Button {
                        togglePrimaryAction()
                    } label: {
                        Text(primaryButtonLabel)
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 84)
                    }
                    .adaptiveGlassButton(
                        prominent: true,
                        tint: active ? KamikazeTheme.hazard : KamikazeTheme.ion
                    )
                    .disabled(lineRearmTask != nil)
                    // Stable identity: arming morphs the same surface instead of
                    // replacing the button.
                    .kamikazeGlassID("play-primary-action", in: glassNamespace)
                }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }

    private var availableModes: [PlayMode] {
        var modes: [PlayMode] = [.free, .line]
        if followModeEnabled { modes.append(.follow) }
        if classicModeEnabled { modes.append(.classic) }
        modes.append(.camera)
        return modes
    }

    private var primaryActionTitle: String {
        switch playMode {
        case .free: "THROW"
        case .line: "START LINE"
        case .follow: "START FOLLOW"
        case .classic: "START CLASSIC"
        case .camera: "OPEN CAMERA RUN"
        }
    }

    private var modeSelector: some View {
        Menu {
            ForEach(availableModes) { mode in
                Button {
                    selectMode(mode)
                } label: {
                    Label {
                        VStack(alignment: .leading) {
                            Text(mode.title)
                            Text(mode.detail)
                        }
                    } icon: {
                        Image(systemName: mode == playMode ? "checkmark.circle.fill" : mode.symbol)
                    }
                }
            }
        } label: {
            GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                HStack(spacing: 12) {
                    Image(systemName: playMode.symbol)
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(KamikazeTheme.volt)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GAME MODE  /  \(playMode.title)")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                        Text(playMode.detail)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(KamikazeTheme.ion)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
            }
        }
        .buttonStyle(.plain)
        .disabled(isCapturingMotion)
        .accessibilityHint("Opens the game mode list")
    }

    private var cameraCaptureControl: some View {
        Button {
            Task { await playCamera.toggle() }
        } label: {
            GlassSurface(role: .instrumentHUD, cornerRadius: 19) {
                HStack(spacing: 11) {
                    Image(systemName: playCamera.isEnabled ? "video.fill" : "video.slash")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(playCamera.isEnabled ? KamikazeTheme.volt : KamikazeTheme.muted)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CAMERA V2")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                        Text(playCamera.statusLabel)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(playCamera.isEnabled ? KamikazeTheme.frost : KamikazeTheme.muted)
                    }
                    Spacer()
                    if playCamera.isPreparing {
                        ProgressView().tint(KamikazeTheme.volt)
                    } else {
                        Text(playCamera.isEnabled ? "ON" : "OFF")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(playCamera.isEnabled ? KamikazeTheme.pitch : KamikazeTheme.muted)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                playCamera.isEnabled ? KamikazeTheme.volt : .white.opacity(0.07),
                                in: Capsule()
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
        .buttonStyle(.plain)
        .disabled(active || playCamera.isPreparing || playCamera.isRecording)
        .accessibilityHint("Records front and rear video and places the selfie feed on the moving phone")
    }

    private var lineLatestCard: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 24) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LAST TRICK")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                    if let latest = line.events.last {
                        Text(latest.trickName.uppercased())
                            .font(.system(size: 23, weight: .black, design: .rounded))
                            .tracking(-0.6)
                            .lineLimit(1)
                        Text(latest.recognized ? "SEALED IN THE LINE" : "NO SCORE · KEEP MOVING")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(latest.recognized ? KamikazeTheme.volt : KamikazeTheme.hazard)
                    } else {
                        Text("READY")
                            .font(.system(size: 23, weight: .black, design: .rounded))
                        Text("THROW WHEN YOU WANT")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.volt)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(line.events.last.map { $0.recognized ? "+\($0.points)" : "—" } ?? "0")
                        .font(.system(size: 37, weight: .black, design: .rounded))
                        .tracking(-1.2)
                        .foregroundStyle(line.events.last?.recognized == false ? KamikazeTheme.muted : KamikazeTheme.volt)
                    Text("POINTS")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                }
            }
            .padding(16)
        }
    }

    private var lineHistoryCard: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("THIS LINE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                        Text("\(line.trickCount) \(line.trickCount == 1 ? "TRICK" : "TRICKS")")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    Spacer()
                    Text("\(line.totalScore)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(-1)
                    Text("PTS")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.volt)
                }

                if line.events.isEmpty {
                    Text("Your tricks will build from left to right.")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal) {
                            HStack(spacing: 7) {
                                ForEach(Array(line.events.enumerated()), id: \.element.id) { index, event in
                                    HStack(spacing: 7) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(index + 1)  \(event.trickName.uppercased())")
                                                .font(.system(size: 8, weight: .black, design: .rounded))
                                                .lineLimit(1)
                                            Text(event.recognized ? "+\(event.points)" : "NO SCORE")
                                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                                .foregroundStyle(event.recognized ? KamikazeTheme.volt : KamikazeTheme.hazard)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                                        if index < line.events.count - 1 {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 8, weight: .black))
                                                .foregroundStyle(KamikazeTheme.muted.opacity(0.65))
                                        }
                                    }
                                    .id(event.id)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .onChange(of: line.attemptCount) { _, _ in
                            guard let latestID = line.events.last?.id else { return }
                            withAnimation(.snappy) { proxy.scrollTo(latestID, anchor: .trailing) }
                        }
                    }
                }

                HStack(spacing: 9) {
                    Circle()
                        .fill(lineStatusColor)
                        .frame(width: 8, height: 8)
                    Text(lineStatusLabel)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                    Spacer()
                    if !line.events.isEmpty {
                        Button("CLEAR LINE", systemImage: "arrow.counterclockwise") {
                            withAnimation(.snappy) { line.reset() }
                        }
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.ion)
                    }
                }
            }
            .padding(16)
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

    private var isCapturingMotion: Bool {
        switch run.phase {
        case .motion, .settling: true
        case .ready, .armed, .result, .unknown, .failed: false
        }
    }

    private var primaryButtonLabel: String {
        if playMode == .line {
            if lineRearmTask != nil { return "LOCKING TRICK…" }
            if active { return "PAUSE LINE" }
            return line.attemptCount == 0 ? "START LINE" : "RESUME LINE"
        }
        return active ? "CANCEL" : primaryActionTitle
    }

    private var lineStatusLabel: String {
        if lineRearmTask != nil { return "TRICK SEALED · REARMING" }
        return switch run.phase {
        case .armed: "LISTENING FOR THE NEXT TRICK"
        case .motion: "TRICK IN MOTION"
        case .settling: "WAITING FOR THE CATCH"
        case .failed: "SENSOR NEEDS ATTENTION"
        case .ready, .result, .unknown: "LINE PAUSED"
        }
    }

    private var lineStatusColor: Color {
        switch run.phase {
        case .armed: KamikazeTheme.volt
        case .motion, .settling: KamikazeTheme.hazard
        case .result: KamikazeTheme.volt
        case .ready, .unknown, .failed: KamikazeTheme.muted
        }
    }

    private func togglePrimaryAction() {
        if active {
            lineRearmTask?.cancel()
            lineRearmTask = nil
            run.cancel()
            feedback.play(.cancelled)
            Task { await playCamera.abandonAttempt() }
        } else {
            Task { @MainActor in
                guard await playCamera.beginAttempt() else { return }
                run.arm()
            }
        }
    }

    private func selectMode(_ mode: PlayMode) {
        guard mode != playMode, !isCapturingMotion else { return }
        lineRearmTask?.cancel()
        lineRearmTask = nil

        if run.result != nil {
            run.dismissResult()
        } else if active {
            run.cancel()
        }

        if mode == .camera {
            run.stop()
            Task { @MainActor in
                await playCamera.disable()
                showsCameraRun = true
            }
            return
        }

        withAnimation(.snappy) { playMode = mode }
        switch mode {
        case .line:
            scheduleLineRearm(delay: .milliseconds(180))
        case .free, .follow, .classic:
            run.start()
        case .camera:
            break
        }
    }

    private func recordCurrentLineResult() {
        guard playMode == .line, let result = run.result else { return }
        let recognized = result.match.status == .recognized
        let points = recognized ? (result.evaluation.score?.value ?? 0) : 0
        withAnimation(.snappy) {
            line.record(LineTrickEvent(
                id: result.id,
                trickName: result.displayName,
                points: points,
                recognized: recognized
            ))
        }
        scheduleLineRearm(delay: playCamera.isEnabled ? .milliseconds(1_050) : .milliseconds(700))
    }

    private func scheduleLineRearm(delay: Duration) {
        lineRearmTask?.cancel()
        lineRearmTask = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, playMode == .line else { return }
            lineRearmTask = nil
            if run.result != nil {
                run.dismissResultAndRearm()
            } else if !active {
                run.arm()
            }
        }
    }

    private func advanceFollowPrompt() {
        if followQueue.isEmpty {
            followQueue = FollowPromptDeck.shuffled(avoiding: followPrompt)
        }
        guard !followQueue.isEmpty else { return }
        followPrompt = followQueue.removeFirst()
    }

    private func rearmAfterCameraTake() {
        Task { @MainActor in
            await playCamera.waitUntilAttemptIsSealed()
            run.dismissResultAndRearm()
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

    /// Cue ordering matters: the armed tick fires BEFORE the evidence window
    /// opens; catch/result cues fire only after the capture has closed.
    private func reactToPhase(_ phase: NativeRunPhase) {
        switch phase {
        case .armed:
            feedback.play(.armed)
            feedback.evidenceWindowActive = true
            if playCamera.isEnabled, !playCamera.isRecording {
                Task { @MainActor in
                    guard await playCamera.beginAttempt() else {
                        run.cancel()
                        return
                    }
                }
            }
        case .motion, .settling:
            feedback.evidenceWindowActive = true
        case .result:
            feedback.evidenceWindowActive = false
            feedback.play(.catchResolved)
            // `result` is published before `phase` in NativeRunModel, so the
            // match status is already readable here.
            feedback.playDetectionSound(success: run.result?.match.status == .recognized)
            recordCurrentLineResult()
            if let result = run.result {
                Task { await playCamera.finishAttempt(attemptID: result.id) }
            }
        case .unknown:
            feedback.evidenceWindowActive = false
            feedback.play(.needsReview)
            feedback.playDetectionSound(success: false)
            recordCurrentLineResult()
            if let result = run.result {
                Task { await playCamera.finishAttempt(attemptID: result.id) }
            }
        case .ready, .failed:
            feedback.evidenceWindowActive = false
            if case .failed = phase {
                Task { await playCamera.abandonAttempt() }
            }
        }
    }

}
