import KamikazeMotionCore
import SwiftUI

struct ResultReplayView: View {
    let result: NativeRunResult
    let onAgain: () -> Void
    let onClose: () -> Void
    @State private var replay: ReplayController

    init(result: NativeRunResult, onAgain: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.result = result
        self.onAgain = onAgain
        self.onClose = onClose
        _replay = State(initialValue: ReplayController(
            payload: result.capture.samplePayload,
            boundaries: result.capture.attempt.boundaries
        ))
    }

    var body: some View {
        ZStack {
            KineticBackground(accent: accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        SectionKicker(text: result.match.status == .recognized ? "LANDED / MEASURED" : "REVIEW / MEASURED")
                        Spacer()
                        Button("Close", systemImage: "xmark") { onClose() }
                            .labelStyle(.iconOnly)
                            .adaptiveGlassButton()
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text(result.displayName)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .tracking(-1.5)
                        Spacer()
                        Text("\(result.fit)")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(accent)
                    }
                    Text(result.match.status == .recognized
                        ? "FIT · provisional rule match, not a calibrated confidence."
                        : "FIT · saved for review. The proposed name is not a final call.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)

                    if let proposedName = result.proposedName {
                        Text("PROPOSED MATCH  /  \(proposedName.uppercased())")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.hazard)
                    }

                    ReplayPhoneView(controller: replay, accent: accent)

                    GlassSurface(level: .subtle, cornerRadius: 20) {
                        HStack {
                            stat("DURATION", "\(result.durationMs) MS")
                            stat("EVIDENCE", "\(result.capture.samplePayload.samples.count) SAMPLES")
                            stat("STATUS", result.match.status.rawValue.uppercased())
                        }
                        .padding(16)
                    }

                    Button("THROW AGAIN") { onAgain() }
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.ion)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
        }
        .onAppear { replay.play() }
    }

    private var accent: Color {
        result.match.status == .recognized ? KamikazeTheme.volt : KamikazeTheme.hazard
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced))
            Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
