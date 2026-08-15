import SwiftUI

struct KamikazeRootView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var selectedTab = AppTab.initialTab
    @State private var experience = ExperienceCoordinator()
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
                Tab(AppTab.profile.title, systemImage: AppTab.profile.symbol, value: AppTab.profile) {
                    NavigationStack { ProfileView(onReplayOnboarding: { onboardingComplete = false }) }
                }
            }
            .environment(experience)
            .tint(KamikazeTheme.volt)
            .preferredColorScheme(.dark)
            .onAppear { experience.setReduceEffects(reduceMotion) }
            .onChange(of: reduceMotion) { _, reduced in
                experience.setReduceEffects(reduced)
            }
            .onChange(of: selectedTab) { _, tab in
                experience.setAmbient(accent: tab.ambientAccent)
            }
        } else {
            OnboardingView(onComplete: { onboardingComplete = true })
                .preferredColorScheme(.dark)
        }
    }
}
