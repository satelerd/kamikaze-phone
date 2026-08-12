import SwiftUI

enum KamikazeTheme {
    static let pitch = Color(red: 0.035, green: 0.04, blue: 0.038)
    static let frost = Color(red: 0.92, green: 0.93, blue: 0.91)
    static let muted = Color(red: 0.60, green: 0.62, blue: 0.59)
    static let ion = Color(red: 0.30, green: 0.40, blue: 1.00)
    static let hazard = Color(red: 1.00, green: 0.38, blue: 0.31)
    static let volt = Color(red: 0.84, green: 1.00, blue: 0.29)
}

struct KineticBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            KamikazeTheme.pitch
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.54, 0.46], [1, 0.55],
                    [0, 1], [0.48, 1], [1, 1],
                ],
                colors: [
                    KamikazeTheme.pitch, KamikazeTheme.pitch, accent.opacity(0.30),
                    accent.opacity(0.14), KamikazeTheme.pitch, KamikazeTheme.hazard.opacity(0.12),
                    KamikazeTheme.pitch, accent.opacity(0.18), KamikazeTheme.pitch,
                ]
            )
            .blur(radius: 28)
            .opacity(0.9)
        }
        .ignoresSafeArea()
    }
}
