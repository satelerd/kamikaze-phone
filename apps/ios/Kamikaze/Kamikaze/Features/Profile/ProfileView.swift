import KamikazeMotionCore
import SwiftUI

struct ProfileView: View {
    static let recentLimit = 6

    let onReplayOnboarding: () -> Void
    @State private var model = ProfileModel()
    @State private var selectedAttempt: NativeRunResult?
    @Environment(FeedbackCoordinator.self) private var feedback
    @State private var isEditingName = false
    @State private var draftName = ""

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.volt)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionKicker(text: "PLAYER / LOCAL PROFILE")
                    identityHeader
                    HStack(spacing: 10) {
                        stat("\(model.metrics.currentStreak)", "CURRENT STREAK")
                        stat("\(model.metrics.landedCount)", "LANDED")
                        stat(model.metrics.highFitPercent.map(String.init) ?? "—", "HIGH FIT")
                    }
                    NavigationLink {
                        StatsView(model: model)
                    } label: {
                        GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("ACTIVITY")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(KamikazeTheme.muted)
                                    Spacer()
                                    Text("\(PlayerStatsEngine(summaries: model.allSummaries).activeDayCount) ACTIVE DAYS")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(KamikazeTheme.muted)
                                }
                                ActivityFieldView(
                                    engine: PlayerStatsEngine(summaries: model.allSummaries),
                                    weeks: 10,
                                    cellSize: 20
                                )
                            }
                            .padding(14)
                        }
                    }
                    .buttonStyle(.plain)
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
                            hapticsRow
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

    private var identityHeader: some View {
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
            Text(model.profileStore.joinedLabel)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
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
                            Task {
                                if let result = await model.openAttempt(id: summary.attemptID) {
                                    selectedAttempt = result
                                }
                            }
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

    private var hapticsRow: some View {
        @Bindable var feedback = feedback
        return Toggle(isOn: $feedback.hapticsEnabled) {
            Text("HAPTICS").font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .tint(KamikazeTheme.volt)
        .frame(minHeight: 54)
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
        HStack(spacing: 14) {
            Text(summary.fit.map { String(Int(($0 * 100).rounded())) } ?? "—")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(summary.isRecognized ? KamikazeTheme.volt : KamikazeTheme.hazard)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.displayName)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                Text("\(Int(summary.motionDurationMs.rounded())) MS  ·  \(summary.outcomeLabel)")
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
                Label("Express calibration", systemImage: "bolt.fill")
                Label("Full axis bench", systemImage: "axis.3d")
                Label("Trick studio", systemImage: "waveform.path")
            }
            Section("STATUS") {
                LabeledContent("Reference device", value: "iPhone 15 Plus")
                LabeledContent("Grip", value: "Right")
                LabeledContent("Motion core", value: "Fixture mode")
            }
        }
        .navigationTitle("Sensor Workshop")
    }
}
