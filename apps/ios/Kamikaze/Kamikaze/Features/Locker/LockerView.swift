import SwiftUI

struct LockerView: View {
    @AppStorage("selectedSkin") private var selectedSkin = "ION"
    private let skins: [(String, Color, Int)] = [
        ("ION", KamikazeTheme.ion, 0),
        ("HAZARD", KamikazeTheme.hazard, 180),
        ("VOLT", KamikazeTheme.volt, 520),
        ("GRAPHITE", .gray, 980),
    ]

    var body: some View {
        ZStack {
            KineticBackground(accent: skins.first(where: { $0.0 == selectedSkin })?.1 ?? KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionKicker(text: "LOCKER / YOUR PHONE, YOUR DECK")
                    Text("BUILD YOUR\nSIGNATURE.")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .tracking(-1.8)
                    GlassSurface(level: .subtle, cornerRadius: 36) {
                        RoundedRectangle(cornerRadius: 24)
                            .fill((skins.first(where: { $0.0 == selectedSkin })?.1 ?? KamikazeTheme.ion).gradient)
                            .frame(width: 126, height: 260)
                            .rotation3DEffect(.degrees(-20), axis: (x: 1, y: 1, z: 0))
                            .frame(maxWidth: .infinity, minHeight: 330)
                    }
                    Text("0 POINTS AVAILABLE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.volt)
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                        ForEach(skins, id: \.0) { name, color, cost in
                            Button {
                                if cost == 0 { selectedSkin = name }
                            } label: {
                                GlassSurface(interactive: true, level: selectedSkin == name ? .elevated : .regular, cornerRadius: 22) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        RoundedRectangle(cornerRadius: 15).fill(color).frame(height: 82)
                                        Text(name).font(.system(size: 13, weight: .bold, design: .rounded))
                                        Text(cost == 0 ? (selectedSkin == name ? "EQUIPPED" : "AVAILABLE") : "\(cost) PTS")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundStyle(KamikazeTheme.muted)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
