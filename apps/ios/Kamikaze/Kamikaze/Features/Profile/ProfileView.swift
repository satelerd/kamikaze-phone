import KamikazeMotionCore
import SwiftUI

struct ProfileView: View {
    let onReplayOnboarding: () -> Void
    @State private var model = ProfileModel()
    @State private var selectedAttempt: NativeRunResult?

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.volt)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionKicker(text: "PLAYER / LOCAL PROFILE")
                    Text("SAT")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .tracking(-2)
                    HStack(spacing: 10) {
                        stat("\(model.recognizedCount)", "RECOGNIZED")
                        stat("\(model.bestRun)", "BEST RUN")
                        stat(model.highFit.map(String.init) ?? "—", "HIGH FIT")
                    }
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
                                ForEach(model.visible) { summary in
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
                                    if summary.id != model.visible.last?.id { Divider() }
                                }
                                if model.hasMore {
                                    Button {
                                        Task { await model.loadMore() }
                                    } label: {
                                        if model.isLoadingMore {
                                            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                                        } else {
                                            Text("LOAD MORE  ·  \(model.totalCount - model.visible.count) LEFT")
                                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                                .frame(maxWidth: .infinity, minHeight: 44)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(KamikazeTheme.volt)
                                }
                            }
                        }
                        .padding(18)
                    }
                    if let loadError = model.loadError, !model.visible.isEmpty {
                        Text(loadError)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.hazard)
                    }
                    feedbackExportSection
                    Text("SETTINGS").font(.system(size: 14, weight: .bold, design: .rounded))
                    GlassSurface {
                        VStack(spacing: 0) {
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
                }
            )
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
