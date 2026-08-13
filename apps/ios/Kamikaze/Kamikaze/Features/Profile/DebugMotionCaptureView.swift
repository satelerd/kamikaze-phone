import KamikazeMotionCore
import SwiftUI

struct DebugMotionCaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = DebugMotionRecorder()
    @State private var expectedTrickID = DebugTrickID.phoneFlip
    @State private var gripHand = GripHand.right
    @State private var caseState = DebugPhoneCaseState.unknown
    @State private var condition = DebugMotionCaptureCondition.standard
    @State private var outcome = DebugMotionCaptureOutcome.landed
    @State private var rhythmNotes = ""

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.hazard)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionKicker(text: "WORKSHOP / RAW EVIDENCE")
                    Text("CAPTURE A\nREAL THROW.")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .tracking(-1.6)

                    GlassSurface(level: .subtle, cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(recorder.statusText)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(statusColor)
                                Spacer()
                                Text(recorder.measuredHz > 0 ? "\(Int(recorder.measuredHz.rounded())) HZ" : "— HZ")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                            }
                            Text(recorder.timestampGapCount == 0
                                ? "TIMING: NO OBSERVED GAPS"
                                : "TIMING: \(recorder.timestampGapCount) GAP(S) FLAGGED")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(recorder.timestampGapCount == 0 ? KamikazeTheme.muted : KamikazeTheme.hazard)
                            Text("Debug-only capture. It preserves a short pre-roll and post-roll with raw v3 motion evidence; it does not score this throw.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(KamikazeTheme.muted)
                        }
                        .padding(18)
                    }

                    labelEditor

                    Button {
                        if recorder.isRecording {
                            recorder.endCapture()
                        } else {
                            recorder.beginCapture(label: DebugMotionCaptureLabel(
                                expectedTrickID: expectedTrickID,
                                gripHand: gripHand,
                                caseState: caseState,
                                condition: condition,
                                outcome: outcome,
                                rhythmNotes: rhythmNotes
                            ))
                        }
                    } label: {
                        Text(recorder.isRecording ? "STOP + KEEP POST-ROLL" : "START RAW CAPTURE")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 66)
                    }
                    .adaptiveGlassButton(
                        prominent: true,
                        tint: recorder.isRecording ? KamikazeTheme.hazard : KamikazeTheme.ion
                    )
                    .disabled(recorder.isSaving || recorder.state == .unavailable)

                    if recorder.lastSaved != nil && !recorder.isRecording && !recorder.isSaving {
                        Button("NEW CAPTURE", systemImage: "plus") {
                            recorder.beginCapture(label: DebugMotionCaptureLabel(
                                expectedTrickID: expectedTrickID,
                                gripHand: gripHand,
                                caseState: caseState,
                                condition: condition,
                                outcome: outcome,
                                rhythmNotes: rhythmNotes
                            ))
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .adaptiveGlassButton(tint: KamikazeTheme.frost)
                    }

                    if let saved = recorder.lastSaved {
                        GlassSurface(level: .regular, cornerRadius: 24) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("CAPTURE SAVED")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.volt)
                                Text("\(saved.sampleCount) RAW SAMPLES · V3 JSON")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                ShareLink(item: saved.exportURL) {
                                    Label("SHARE V3 JSON", systemImage: "square.and.arrow.up")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                }
                                .adaptiveGlassButton(tint: KamikazeTheme.volt)
                            }
                            .padding(18)
                        }
                    }

                    if let observation = recorder.automaticObservation {
                        GlassSurface(level: .subtle, cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("AUTO OBSERVATION · NOT GROUND TRUTH")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.hazard)
                                Text("\(observation.trick) · \(Int((observation.confidence * 100).rounded()))%")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                Text(observation.triggerMode?.uppercased() ?? "NO RESOLVED TRIGGER")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                            }
                            .padding(16)
                        }
                    }

                    if case let .failed(message) = recorder.state {
                        Text(message)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.hazard)
                    }
                }
                .padding(20)
                .padding(.bottom, 42)
            }
        }
        .navigationTitle("Debug capture")
        .navigationBarTitleDisplayMode(.inline)
        .task { recorder.start() }
        .onDisappear { recorder.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { recorder.interruptCapture() }
        }
    }

    private var labelEditor: some View {
        GlassSurface(level: .regular, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("LABEL BEFORE RECORDING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                Picker("Expected trick", selection: $expectedTrickID) {
                    ForEach(DebugTrickID.allCases, id: \.self) { trick in
                        Text(trick.title).tag(trick)
                    }
                }
                .pickerStyle(.menu)
                Picker("Grip hand", selection: $gripHand) {
                    Text("RIGHT").tag(GripHand.right)
                    Text("LEFT").tag(GripHand.left)
                }
                .pickerStyle(.menu)
                Picker("Phone case", selection: $caseState) {
                    ForEach(DebugPhoneCaseState.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.menu)
                Picker("Capture condition", selection: $condition) {
                    ForEach(DebugMotionCaptureCondition.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.menu)
                Picker("Outcome", selection: $outcome) {
                    ForEach(DebugMotionCaptureOutcome.allCases, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.menu)
                TextField("Rhythm / setup notes (optional)", text: $rhythmNotes, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(12)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(18)
        }
    }

    private var statusColor: Color {
        switch recorder.state {
        case .recording, .postRoll: KamikazeTheme.hazard
        case .saved: KamikazeTheme.volt
        case .unavailable, .failed: KamikazeTheme.hazard
        default: KamikazeTheme.ion
        }
    }
}
