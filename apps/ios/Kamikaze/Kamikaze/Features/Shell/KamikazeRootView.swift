import SwiftUI

struct KamikazeRootView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var selectedTab = AppTab.initialTab
    @State private var experience = ExperienceCoordinator()
    @State private var appearance = AppearanceStore()
    @State private var feedback = FeedbackCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if selectedPhoneModelIsReady {
            appContent
        } else {
            PhoneModelLaunchView(modelName: appearance.effective.formFactor.displayName)
                .preferredColorScheme(.dark)
                .task {
                    PhoneModelLibrary.shared.preload()
                }
        }
    }

    @ViewBuilder
    private var appContent: some View {
        if onboardingComplete {
            TabView(selection: $selectedTab) {
                Tab(AppTab.play.title, systemImage: AppTab.play.symbol, value: AppTab.play) {
                    NavigationStack { PlayView() }
                }
                Tab(AppTab.practice.title, systemImage: AppTab.practice.symbol, value: AppTab.practice) {
                    NavigationStack { PracticeView() }
                }
                Tab(AppTab.locker.title, systemImage: AppTab.locker.symbol, value: AppTab.locker) {
                    NavigationStack { LockerView() }
                }
                Tab(AppTab.profile.title, systemImage: AppTab.profile.symbol, value: AppTab.profile) {
                    NavigationStack { ProfileView(onReplayOnboarding: { onboardingComplete = false }) }
                }
                Tab(AppTab.beta.title, systemImage: AppTab.beta.symbol, value: AppTab.beta) {
                    NavigationStack { BetaView() }
                }
            }
            .environment(experience)
            .environment(appearance)
            .environment(feedback)
            .tint(KamikazeTheme.volt)
            .preferredColorScheme(.dark)
            .onAppear {
                experience.setReduceEffects(reduceMotion)
                PhoneModelLibrary.shared.preload()
            }
            .onChange(of: reduceMotion) { _, reduced in
                experience.setReduceEffects(reduced)
            }
            .onChange(of: selectedTab) { _, tab in
                experience.setAmbient(accent: tab.ambientAccent)
            }
        } else {
            OnboardingView(onComplete: { onboardingComplete = true })
                .environment(experience)
                .environment(appearance)
                .environment(feedback)
                .preferredColorScheme(.dark)
                .onAppear {
                    experience.setReduceEffects(reduceMotion)
                    PhoneModelLibrary.shared.preload()
                }
        }
    }

    private var selectedPhoneModelIsReady: Bool {
        let library = PhoneModelLibrary.shared
        return PhoneAppearanceLaunchGate.canRender(
            appearance: appearance.effective,
            loadedAssets: Set(library.loaded.keys),
            failedAssets: library.failed
        )
    }
}

/// Startup placeholder for imported models. It intentionally contains no
/// phone geometry: showing the old procedural body for a moment made it look
/// as if the player's equipped model changed on every launch.
private struct PhoneModelLaunchView: View {
    let modelName: String

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.ion)
            VStack(spacing: 14) {
                ProgressView()
                    .tint(KamikazeTheme.volt)
                    .controlSize(.large)
                Text("LOADING \(modelName)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(KamikazeTheme.frost.opacity(0.72))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading your phone model")
    }
}
