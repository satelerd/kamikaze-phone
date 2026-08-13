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
                        stat("\(model.landedCount)", "LANDED")
                        stat("\(model.bestRun)", "BEST RUN")
                        stat(model.highFit.map(String.init) ?? "—", "HIGH FIT")
                    }
                    GlassSurface {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("RECENT").font(.system(size: 12, weight: .bold, design: .monospaced))
                                Spacer()
                                Text("\(model.recent.count) SAVED")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                            }
                            if model.isLoading && model.recent.isEmpty {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                            } else if let loadError = model.loadError {
                                ContentUnavailableView("Could not load attempts", systemImage: "exclamationmark.triangle", description: Text(loadError))
                                    .frame(maxWidth: .infinity, minHeight: 170)
                            } else if model.recent.isEmpty {
                                ContentUnavailableView("No attempts yet", systemImage: "waveform.path.ecg", description: Text("Your first native run will appear here."))
                                    .frame(maxWidth: .infinity, minHeight: 170)
                            } else {
                                ForEach(model.recent) { attempt in
                                    Button { selectedAttempt = attempt } label: {
                                        recentRow(attempt)
                                    }
                                    .buttonStyle(.plain)
                                    if attempt.id != model.recent.last?.id { Divider() }
                                }
                            }
                        }
                        .padding(18)
                    }
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
                onClose: { selectedAttempt = nil }
            )
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

    private func recentRow(_ attempt: NativeRunResult) -> some View {
        HStack(spacing: 14) {
            Text("\(attempt.fit)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(attempt.match.status == .recognized ? KamikazeTheme.volt : KamikazeTheme.hazard)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(attempt.displayName)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                Text("\(attempt.durationMs) MS  ·  \(attempt.match.status.rawValue.uppercased())")
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
