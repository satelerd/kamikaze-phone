import SwiftUI

struct PracticeView: View {
    private let levels = ["BACKSIDE SHUVIT", "FRONTSIDE SHUVIT", "PHONE FLIP", "REVERSE PHONE FLIP", "FLIP", "REVERSE FLIP"]

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.hazard)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    SectionKicker(text: "PRACTICE / SIX LEVELS")
                    Text("BUILD THE\nMUSCLE MEMORY.")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(-1.8)
                    ForEach(Array(levels.enumerated()), id: \.offset) { index, name in
                        GlassSurface(interactive: index == 0) {
                            HStack(spacing: 16) {
                                Text(String(format: "%02d", index + 1))
                                    .font(.system(size: 25, weight: .black, design: .rounded))
                                    .foregroundStyle(index == 0 ? KamikazeTheme.volt : KamikazeTheme.muted)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name).font(.system(size: 15, weight: .bold, design: .rounded))
                                    Text(index == 0 ? "READY TO START" : "LAND THE PREVIOUS LEVEL")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(KamikazeTheme.muted)
                                }
                                Spacer()
                                Image(systemName: index == 0 ? "play.fill" : "lock.fill")
                            }
                            .padding(18)
                        }
                        .opacity(index == 0 ? 1 : 0.48)
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
