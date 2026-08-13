import KamikazeMotionCore
import SwiftUI

struct DebugMotionCaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = DebugMotionRecorder()
    @State private var expectedTrickID = DebugTrickID.phoneFlip
    @State private var gripHand = GripHand.right
    @State private var caseState = DebugPhoneCaseState.unknown

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.hazard)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionKicker(text: "TRICK LAB / LABELLED EVIDENCE")
                    Text("TEACH THE\nDETECTOR.")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .tracking(-1.6)

                    sensorStatus
                    measurementGuide
                    intentionEditor

                    Button {
                        if recorder.isRecording {
                            recorder.endCapture()
                        } else {
                            recorder.beginCapture(label: initialLabel)
                        }
                    } label: {
                        Text(recorder.isRecording ? "STOP AFTER CATCH" : "START LABELLED CAPTURE")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 72)
                    }
                    .adaptiveGlassButton(
                        prominent: true,
                        tint: recorder.isRecording ? KamikazeTheme.hazard : KamikazeTheme.ion
                    )
                    .disabled(recorder.isSaving || recorder.state == .unavailable || recorder.reviewDraft != nil)

                    if recorder.isRecording {
                        Text("Do the throw, catch it, then tap STOP. The recorder keeps 350 ms before and after your markers.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                    }

                    if let saved = recorder.lastSaved {
                        savedCard(saved)
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
        .navigationTitle("Trick Lab")
        .navigationBarTitleDisplayMode(.inline)
        .task { recorder.start() }
        .onDisappear {
            if recorder.reviewDraft == nil { recorder.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active, recorder.isRecording { recorder.interruptCapture() }
        }
        .fullScreenCover(item: Binding(
            get: { recorder.reviewDraft },
            set: { if $0 == nil { recorder.discardReview() } }
        )) { draft in
            TrickCaptureReviewView(
                draft: draft,
                onSave: recorder.saveReviewedCapture,
                onRetake: recorder.discardReview
            )
        }
    }

    private var initialLabel: DebugMotionCaptureLabel {
        DebugMotionCaptureLabel(
            expectedTrickID: expectedTrickID,
            gripHand: gripHand,
            caseState: caseState,
            condition: .standard,
            outcome: .unclear,
            rhythmNotes: ""
        )
    }

    private var sensorStatus: some View {
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
                Text("Choose your intention first. You label the outcome only after reviewing the measured replay.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .padding(18)
        }
    }

    private var measurementGuide: some View {
        GlassSurface(level: .subtle, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("WHAT THIS RECORDS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
                Text("Intended trick · landed or missed · speed/height condition · grip/case · raw X/Y/Z rotation · acceleration · fused 3D pose · timing quality · detector proposal.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .padding(18)
        }
    }

    private var intentionEditor: some View {
        GlassSurface(level: .regular, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("1 / CHOOSE YOUR INTENTION")
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
                Text("You will mark LANDED, MISSED, the throw condition and notes after watching the replay.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            .padding(18)
        }
    }

    private func savedCard(_ saved: DebugSavedMotionCapture) -> some View {
        GlassSurface(level: .regular, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("CAPTURE VERIFIED + SAVED")
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

    private var statusColor: Color {
        switch recorder.state {
        case .recording, .postRoll: KamikazeTheme.hazard
        case .saved: KamikazeTheme.volt
        case .unavailable, .failed: KamikazeTheme.hazard
        default: KamikazeTheme.ion
        }
    }
}

private struct TrickCaptureReviewView: View {
    let draft: DebugMotionCaptureDraft
    let onSave: (DebugMotionCaptureLabel) -> Void
    let onRetake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var expectedTrickID: DebugTrickID
    @State private var condition: DebugMotionCaptureCondition
    @State private var outcome = DebugMotionCaptureOutcome.unclear
    @State private var notes: String
    @State private var replay: ReplayController

    init(
        draft: DebugMotionCaptureDraft,
        onSave: @escaping (DebugMotionCaptureLabel) -> Void,
        onRetake: @escaping () -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onRetake = onRetake
        _expectedTrickID = State(initialValue: draft.proposedLabel.expectedTrickID)
        _condition = State(initialValue: draft.proposedLabel.condition)
        _notes = State(initialValue: draft.proposedLabel.rhythmNotes)
        _replay = State(initialValue: ReplayController(
            payload: draft.capture.samplePayload,
            boundaries: draft.capture.attempt.boundaries
        ))
    }

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.hazard)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        SectionKicker(text: "TRICK LAB / REVIEW")
                        Spacer()
                        Button("Retake", systemImage: "arrow.counterclockwise") {
                            onRetake()
                            dismiss()
                        }
                        .labelStyle(.iconOnly)
                        .adaptiveGlassButton()
                    }
                    Text("WHAT ACTUALLY\nHAPPENED?")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-1.5)

                    ReplayPhoneView(controller: replay, accent: KamikazeTheme.ion)

                    if let observation = draft.automaticObservation {
                        GlassSurface(level: .subtle, cornerRadius: 20) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("DETECTOR PROPOSAL · NOT GROUND TRUTH")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.hazard)
                                Text("\(observation.trick) · \(Int((observation.confidence * 100).rounded())) FIT")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .padding(16)
                        }
                    }

                    labelReview

                    Button("CONFIRM + SAVE EVIDENCE") {
                        onSave(reviewedLabel)
                    }
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 68)
                    .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)

                    Text("UNCLEAR is a valid exploration label. It will be kept out of strict landed/missed evaluation until you review it later.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                .padding(20)
                .padding(.bottom, 36)
            }
        }
        .onAppear { replay.play() }
    }

    private var labelReview: some View {
        GlassSurface(level: .regular, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("2 / HUMAN LABEL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
                Picker("Intended trick", selection: $expectedTrickID) {
                    ForEach(DebugTrickID.allCases, id: \.self) { trick in
                        Text(trick.title).tag(trick)
                    }
                }
                Picker("What happened?", selection: $outcome) {
                    ForEach(DebugMotionCaptureOutcome.allCases.filter { $0 != .calibration }, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                Picker("Throw condition", selection: $condition) {
                    ForEach(DebugMotionCaptureCondition.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }
                TextField("What was unusual? (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2 ... 4)
                    .padding(12)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(18)
        }
    }

    private var reviewedLabel: DebugMotionCaptureLabel {
        DebugMotionCaptureLabel(
            expectedTrickID: expectedTrickID,
            gripHand: draft.proposedLabel.gripHand,
            caseState: draft.proposedLabel.caseState,
            condition: condition,
            outcome: outcome,
            rhythmNotes: notes
        )
    }
}
