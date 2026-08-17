import SwiftUI

struct KamikazeRootView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var selectedTab = AppTab.initialTab
    @State private var experience = ExperienceCoordinator()
    @State private var appearance = AppearanceStore()
    @State private var feedback = FeedbackCoordinator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
                Tab(AppTab.beta.title, systemImage: AppTab.beta.symbol, value: AppTab.beta) {
                    NavigationStack { BetaView() }
                }
                Tab(AppTab.profile.title, systemImage: AppTab.profile.symbol, value: AppTab.profile) {
                    NavigationStack { ProfileView(onReplayOnboarding: { onboardingComplete = false }) }
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
}
