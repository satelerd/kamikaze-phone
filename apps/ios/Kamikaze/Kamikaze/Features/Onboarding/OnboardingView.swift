import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let body: String
    let symbol: String
    let accent: Color
}

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page = 0

    private let pages = [
        OnboardingPage(id: 0, title: "YOUR PHONE\nIS THE BOARD.", body: "Throw it. Rotate it. Catch it. Kamikaze reads the motion and scores the landing.", symbol: "iphone.gen3.radiowaves.left.and.right", accent: KamikazeTheme.ion),
        OnboardingPage(id: 1, title: "CHOOSE YOUR\nLEVEL OF CHAOS.", body: "A case and a soft landing zone are smart. Going case-free is extremely Kamikaze—and entirely your call.", symbol: "shield.lefthalf.filled", accent: KamikazeTheme.hazard),
        OnboardingPage(id: 2, title: "ZERO. THROW.\nLAND.", body: "Hold the phone naturally, zero its pose, then start with one clean Phone Flip.", symbol: "gyroscope", accent: KamikazeTheme.volt),
    ]

    var body: some View {
        ZStack {
            KineticBackground(accent: pages[page].accent)
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages) { item in
                        VStack(alignment: .leading, spacing: 24) {
                            Spacer()
                            Image(systemName: item.symbol)
                                .font(.system(size: 76, weight: .light))
                                .foregroundStyle(item.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 30)
                            Text(item.title)
                                .font(.system(size: 43, weight: .black, design: .rounded))
                                .tracking(-2)
                                .foregroundStyle(KamikazeTheme.frost)
                            Text(item.body)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(KamikazeTheme.muted)
                                .lineSpacing(5)
                            Spacer()
                        }
                        .padding(.horizontal, 26)
                        .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                Button(page == pages.count - 1 ? "ENTER KAMIKAZE" : "CONTINUE") {
                    if page == pages.count - 1 { onComplete() }
                    else { withAnimation(.snappy) { page += 1 } }
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 66)
                .adaptiveGlassButton(prominent: true, tint: pages[page].accent)
                .padding(22)
            }
        }
    }
}
