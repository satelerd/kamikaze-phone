import KamikazeMotionCore
import SwiftUI

/// Original Kamikaze: orientation is replayed for context, but the result is
/// exclusively air time and a transparent ballistic height estimate.
struct ClassicResultView: View {
    let result: NativeRunResult
    let onAgain: () -> Void
    let onClose: () -> Void

    @State private var replay: ReplayController
    private let freefall: FreefallWindow?

    init(
        result: NativeRunResult,
        onAgain: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.result = result
        self.onAgain = onAgain
        self.onClose = onClose
        let frames = ReplayBuilder.normalized(ReplayBuilder.buildFrames(
            payload: result.capture.samplePayload,
            boundaries: result.capture.attempt.boundaries
        ))
        freefall = ReplayBuilder.freefallWindow(in: frames)
        _replay = State(initialValue: ReplayController(frames: frames))
    }

    var body: some View {
        ZStack {
            SlipstreamField(accent: KamikazeTheme.hazard, energy: 0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("KAMIKAZE\nCLASSIC")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .tracking(-1.5)
                        Spacer()
                        Button("Close", systemImage: "xmark") { onClose() }
                            .labelStyle(.iconOnly)
                            .adaptiveGlassButton()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(heightLabel)
                            .font(.system(size: 76, weight: .black, design: .rounded))
                            .foregroundStyle(KamikazeTheme.volt)
                        Text(freefall == nil ? "NO RELIABLE AIR WINDOW" : "ESTIMATED PEAK HEIGHT")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                    }

                    ReplayPhoneView(
                        controller: replay,
                        accent: KamikazeTheme.hazard,
                        arcWindow: freefall
                    )

                    Button("THROW AGAIN") { onAgain() }
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 122)
                        .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.hazard)

                    GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                metric("AIR TIME", airTimeLabel)
                                metric("EST. HEIGHT", heightLabel)
                                metric("TRIGGER", result.capture.attempt.triggerMode?.rawValue.uppercased() ?? "—")
                            }
                            Divider().overlay(.white.opacity(0.1))
                            Text("Air time is measured from the low-g window. Height uses h = g·T²/8 and assumes release and catch at roughly the same height. The IMU does not directly track vertical position.")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(KamikazeTheme.muted)
                        }
                        .padding(16)
                    }
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .onAppear { replay.play() }
        .onDisappear { replay.pause() }
    }

    private var heightLabel: String {
        guard let freefall else { return "— CM" }
        return "\(Int((freefall.peakHeightM * 100).rounded())) CM"
    }

    private var airTimeLabel: String {
        guard let freefall else { return "— MS" }
        return "\(Int((freefall.durationS * 1_000).rounded())) MS"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 12, weight: .black, design: .monospaced))
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
