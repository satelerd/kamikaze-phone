import SwiftUI

struct ProfileView: View {
    let onReplayOnboarding: () -> Void

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
                        stat("0", "TRICKS")
                        stat("0", "BEST RUN")
                        stat("—", "HIGH SCORE")
                    }
                    GlassSurface {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("RECENT").font(.system(size: 12, weight: .bold, design: .monospaced))
                            ContentUnavailableView("No attempts yet", systemImage: "waveform.path.ecg", description: Text("Your first native run will appear here."))
                                .frame(maxWidth: .infinity, minHeight: 170)
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
}

struct WorkshopView: View {
    var body: some View {
        List {
            Section("CALIBRATION") {
#if DEBUG
                NavigationLink {
                    DebugMotionCaptureView()
                } label: {
                    Label("Capture / export raw v3", systemImage: "record.circle")
                }
#endif
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
