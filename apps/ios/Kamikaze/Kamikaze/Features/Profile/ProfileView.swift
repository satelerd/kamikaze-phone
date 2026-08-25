import KamikazeMotionCore
import SwiftUI

struct ProfileView: View {
    @AppStorage(BetaFlags.resultMetric) private var resultMetricRaw = ResultMetricMode.default.rawValue
    static let recentLimit = 6

    let onReplayOnboarding: () -> Void
    @State private var model = ProfileModel()
    @State private var selectedAttempt: NativeRunResult?
    @State private var isEditingName = false
    @State private var draftName = ""
    @Environment(AppearanceStore.self) private var appearance

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.volt)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identityHeader
                    riderStage
                    nextSkillCard
                    communityCard
                    motionTapeCard
                    activityCard
                    recentCard
                    HStack(spacing: 10) {
                        NavigationLink {
                            HistoryView(model: model)
                        } label: {
                            Text("ALL HISTORY  ·  \(model.totalCount)")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .adaptiveGlassButton(tint: KamikazeTheme.ion)
                        NavigationLink {
                            StatsView(model: model)
                        } label: {
                            Text("ALL STATS")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .adaptiveGlassButton(tint: KamikazeTheme.ion)
                    }
                    feedbackExportSection
                    Text("SETTINGS").font(.system(size: 14, weight: .bold, design: .rounded))
                    GlassSurface {
                        VStack(spacing: 0) {
                            Button {
                                draftName = model.profileStore.name
                                isEditingName = true
                            } label: {
                                settingsRow("RIDER NAME", value: model.profileStore.name)
                            }
                            .buttonStyle(.plain)
                            Divider()
                            settingsRow("GRIP HAND", value: "RIGHT")
                            Divider()
                            Button(action: onReplayOnboarding) { settingsRow("REPLAY HOW TO PLAY", value: "→") }
                                .buttonStyle(.plain)
                            Divider()
                            NavigationLink { WorkshopView() } label: { settingsRow("SENSOR WORKSHOP", value: "→") }
                                .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Task { await model.refresh() } }
        .alert("Rider name", isPresented: $isEditingName) {
            TextField("Name", text: $draftName)
            Button("Save") { model.profileStore.rename(to: draftName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown only on this phone.")
        }
        .fullScreenCover(item: $selectedAttempt) { attempt in
            ResultReplayView(
                result: attempt,
                primaryTitle: "BACK TO RECENT",
                onAgain: { selectedAttempt = nil },
                onClose: { selectedAttempt = nil },
                onReview: { review in
                    guard let updated = await model.applyHumanReview(
                        attemptID: attempt.id,
                        review: review,
                        current: attempt
                    ) else { return nil }
                    selectedAttempt = updated
                    return updated
                },
                onDelete: {
                    if await model.deleteAttempt(id: attempt.id) {
                        selectedAttempt = nil
                    }
                }
            )
        }
    }

    /// One engine build per render, shared by the label and the grid.
    private var activityCard: some View {
        let engine = PlayerStatsEngine(summaries: model.allSummaries)
        return NavigationLink {
            StatsView(model: model)
        } label: {
            GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ACTIVITY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                        Spacer()
                        Text("\(engine.activeDayCount) ACTIVE DAYS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                    ActivityFieldView(engine: engine, weeks: 10, cellSize: 20)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
    }

    private var identityHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    draftName = model.profileStore.name
                    isEditingName = true
                } label: {
                    Text(model.profileStore.name)
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .tracking(-2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .buttonStyle(.plain)
                Text("PHONE FLIP RIDER  ·  \(appearance.effective.formFactor.displayName)")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
                Text(model.profileStore.joinedLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NavigationLink {
                ClerkAccountSurface(clerk: KamikazeIdentityConfiguration.clerk)
            } label: {
                Label(
                    KamikazeIdentityConfiguration.hasActiveUser ? "ACCOUNT" : "SIGN IN",
                    systemImage: KamikazeIdentityConfiguration.hasActiveUser
                        ? "person.crop.circle.fill.badge.checkmark"
                        : "person.crop.circle.badge.plus"
                )
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .frame(minWidth: 96, minHeight: 50)
            }
            .adaptiveGlassButton(
                prominent: !KamikazeIdentityConfiguration.hasActiveUser,
                tint: KamikazeIdentityConfiguration.hasActiveUser
                    ? KamikazeTheme.ion
                    : KamikazeTheme.volt
            )
        }
    }

    /// Profile identity is the configured phone, not an avatar placeholder.
    /// It reuses the same RealityKit scene and gestures as Play and Setup.
    private var riderStage: some View {
        GlassSurface(role: .stage, cornerRadius: 34) {
            ZStack(alignment: .bottomLeading) {
                LivePhoneScene(
                    attitude: .identity,
                    accent: KamikazeTheme.ion,
                    initialYaw: -0.58,
                    initialPitch: 0.18,
                    initialZoom: 0.39
                )
                .frame(height: 290)

                GlassSurface(role: .instrumentHUD, cornerRadius: 17) {
                    HStack(spacing: 16) {
                        heroStat("\(model.metrics.currentStreak)", "STREAK")
                        heroStat("\(model.metrics.successCount)", "LANDED")
                        heroStat("\(model.metrics.bestStreak)", "BEST")
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                }
                .frame(maxWidth: 224)
                .padding(12)
            }
        }
    }

    /// Community is a player destination, not a developer switch. The feed is
    /// still backed by the local preview repository, so the card promises
    /// discovery and sharing intent without implying that cloud sync is live.
    private var communityCard: some View {
        NavigationLink {
            SocialFeedView()
        } label: {
            GlassSurface(role: .interactiveCard, cornerRadius: 24) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(KamikazeTheme.ion.opacity(0.17))
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(KamikazeTheme.ion)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMUNITY  /  LOCAL PREVIEW")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.ion)
                        Text("FOLLOW THE THROW")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("See shared runs, react and test the social flow before cloud publishing goes live.")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(KamikazeTheme.ion)
                }
                .padding(15)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var nextSkillCard: some View {
        let progress = PracticeProgress(summaries: model.allSummaries)
        if let goal = progress.nextGoal(),
           let pair = PracticeLibrary.pairs.first(where: { $0.order == goal.pairOrder }),
           let node = pair.tricks.first(where: { $0.trickID == goal.trickID }) {
            NavigationLink {
                PracticeLevelView(node: node, pair: pair)
            } label: {
                GlassSurface(role: .interactiveCard, cornerRadius: 22) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NEXT SKILL  /  \(pair.title)")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.muted)
                            Text(goal.trickID.displayName)
                                .font(.system(size: 19, weight: .black, design: .rounded))
                            Text(node.coachingCue)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(KamikazeTheme.muted)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(min(goal.cleanReps, goal.requiredReps))/\(goal.requiredReps)")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .tracking(-1.4)
                                .foregroundStyle(KamikazeTheme.volt)
                            Text("CLEAN REPS")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.muted)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(KamikazeTheme.volt)
                    }
                    .padding(16)
                }
            }
            .buttonStyle(.plain)
        } else {
            GlassSurface(role: .interactiveCard, cornerRadius: 22) {
                HStack(spacing: 13) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(KamikazeTheme.volt)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CURRENT LADDER MASTERED")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                        Text("New skills unlock when their detector evidence is ready.")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private var motionTapeCard: some View {
        if !model.allSummaries.isEmpty {
            GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
                MotionTapeView(summaries: model.allSummaries) { attemptID in
                    openAttempt(attemptID)
                }
                .padding(15)
            }
        }
    }

    private var recentCard: some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("RECENT").font(.system(size: 12, weight: .bold, design: .monospaced))
                    Spacer()
                    Text("\(model.totalCount) SAVED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                if model.isLoading && model.visible.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else if let loadError = model.loadError, model.visible.isEmpty {
                    ContentUnavailableView("Could not load attempts", systemImage: "exclamationmark.triangle", description: Text(loadError))
                        .frame(maxWidth: .infinity, minHeight: 170)
                } else if model.visible.isEmpty {
                    ContentUnavailableView("No attempts yet", systemImage: "waveform.path.ecg", description: Text("Your first native run will appear here."))
                        .frame(maxWidth: .infinity, minHeight: 170)
                } else {
                    let recent = model.visible.prefix(Self.recentLimit)
                    ForEach(recent) { summary in
                        Button {
                            openAttempt(summary.attemptID)
                        } label: {
                            recentRow(summary)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isOpeningAttempt)
                        if summary.id != recent.last?.id { Divider() }
                    }
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var feedbackExportSection: some View {
        if model.reviewedCount > 0 {
            if let url = model.feedbackExportURL {
                ShareLink(item: url) {
                    Label("SHARE PLAYER FEEDBACK", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .adaptiveGlassButton(tint: KamikazeTheme.volt)
            } else {
                Button {
                    Task { await model.prepareFeedbackExport() }
                } label: {
                    if model.isExportingFeedback {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 54)
                    } else {
                        Label("EXPORT PLAYER FEEDBACK  ·  \(model.reviewedCount)", systemImage: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                }
                .adaptiveGlassButton(tint: KamikazeTheme.volt)
                .disabled(model.isExportingFeedback)
            }
            if let exportError = model.feedbackExportError {
                Text(exportError)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.hazard)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 5) {
                Text(value).font(.system(size: 27, weight: .black, design: .rounded))
                Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
        }
    }

    private func heroStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 21, weight: .black, design: .rounded))
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
        }
    }

    private func openAttempt(_ attemptID: String) {
        Task {
            if let result = await model.openAttempt(id: attemptID) {
                selectedAttempt = result
            }
        }
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .bold, design: .rounded))
            Spacer()
            Text(value).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.volt)
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private func recentRow(_ summary: AttemptSummaryV1) -> some View {
        let metric = ResultMetricMode(rawValue: resultMetricRaw) ?? .default
        let showsFit = metric == .legacyFit
        let value = showsFit
            ? summary.fit.map { String(Int(($0 * 100).rounded())) }
            : summary.gameScore.map(String.init)
        return HStack(spacing: 14) {
            Text(value ?? "—")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(summary.gameScore != nil || summary.isRecognized ? KamikazeTheme.volt : KamikazeTheme.hazard)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.displayName)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                Text("\(showsFit ? "FIT" : "SCORE")  ·  \(Int(summary.motionDurationMs.rounded())) MS  ·  \(summary.outcomeLabel)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(KamikazeTheme.muted)
        }
        .contentShape(Rectangle())
    }
}

struct WorkshopView: View {
    var body: some View {
        List {
            Section("CALIBRATION") {
                NavigationLink {
                    DebugMotionCaptureView()
                } label: {
                    Label("Trick Lab", systemImage: "waveform.badge.magnifyingglass")
                }
                NavigationLink {
                    ExpressCalibrationView()
                } label: {
                    Label("Express calibration", systemImage: "bolt.fill")
                }
                Label("Full axis bench · next", systemImage: "axis.3d")
                Label("Trick studio · next", systemImage: "waveform.path")
            }
            Section("STATUS") {
                LabeledContent("Reference device", value: "iPhone 15 Plus")
                LabeledContent("Grip", value: "Right")
                LabeledContent("Motion core", value: "Native v3")
            }
        }
        .navigationTitle("Sensor Workshop")
    }
}
