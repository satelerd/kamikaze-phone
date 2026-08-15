import KamikazeMotionCore
import SwiftUI

struct DebugMotionCaptureView: View {
    private enum LabMode: String, CaseIterable {
        case library = "PICK A TRICK"
        case guided = "GUIDED"
    }

    private struct GuidedStep: Identifiable {
        let id: Int
        let trick: DebugTrickID
        let condition: DebugMotionCaptureCondition
        let prompt: String
    }

    private struct TrickShelf: Identifiable {
        let id: String
        let subtitle: String
        let tricks: [DebugTrickID]
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var recorder = DebugMotionRecorder()
    @State private var expectedTrickID = DebugTrickID.phoneFlip
    @State private var gripHand = GripHand.right
    @State private var caseState = DebugPhoneCaseState.unknown
    @State private var labMode = LabMode.library
    @State private var guidedIndex = 0

    private let guidedSteps: [GuidedStep] = {
        let tricks: [DebugTrickID] = [
            .flip, .reverseFlip, .phoneFlip, .reversePhoneFlip,
            .backsideThreeSixtyShuvit, .frontsideThreeSixtyShuvit,
        ]
        let variations: [(DebugMotionCaptureCondition, String)] = [
            (.standard, "LAND IT AT YOUR NATURAL HEIGHT AND SPEED"),
            (.highFreefall, "LAND A CLEAR, HIGHER THROW"),
            (.fastLow, "LAND IT FAST AND LOW"),
            (.negativeControl, "INTENTIONALLY MISS OR UNDER-ROTATE IT"),
        ]
        return tricks.flatMap { trick in variations.map { (trick, $0.0, $0.1) } }
            .enumerated()
            .map { GuidedStep(id: $0.offset, trick: $0.element.0, condition: $0.element.1, prompt: $0.element.2) }
    }()

    private let trickShelves: [TrickShelf] = [
        TrickShelf(
            id: "FLIP FAMILY",
            subtitle: "ONE ROTATION · PHYSICALLY VALIDATED",
            tricks: [.flip, .reverseFlip, .phoneFlip, .reversePhoneFlip]
        ),
        TrickShelf(
            id: "SHUVIT FAMILY",
            subtitle: "180° BASE · 360° FULL ROTATION",
            tricks: [
                .backsideShuvit, .frontsideShuvit,
                .backsideThreeSixtyShuvit, .frontsideThreeSixtyShuvit,
            ]
        ),
        TrickShelf(
            id: "DOUBLE FAMILY",
            subtitle: "TWO ROTATIONS · NEEDS LABELLED EVIDENCE",
            tricks: [
                .doubleFlip, .doubleReverseFlip,
                .doublePhoneFlip, .doubleReversePhoneFlip,
            ]
        ),
        TrickShelf(
            id: "CONTROL",
            subtitle: "NO ROTATION OR NO VALID TRICK",
            tricks: [.straightAir, .unknown]
        ),
    ]

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
                    modeSelector
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

                    if let dataset = recorder.labelledDatasetExport {
                        datasetCard(dataset)
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
                onSave: { label in
                    recorder.saveReviewedCapture(label: label)
                    if labMode == .guided, guidedIndex < guidedSteps.count - 1 {
                        guidedIndex += 1
                    }
                },
                onRetake: recorder.discardReview
            )
        }
    }

    private var initialLabel: DebugMotionCaptureLabel {
        DebugMotionCaptureLabel(
            expectedTrickID: labMode == .guided ? guidedStep.trick : expectedTrickID,
            gripHand: gripHand,
            caseState: caseState,
            condition: labMode == .guided ? guidedStep.condition : .standard,
            outcome: .unclear,
            rhythmNotes: ""
        )
    }

    private var guidedStep: GuidedStep {
        guidedSteps[min(guidedIndex, guidedSteps.count - 1)]
    }

    private var modeSelector: some View {
        HStack(spacing: 8) {
            ForEach(LabMode.allCases, id: \.self) { mode in
                Button(mode.rawValue) { labMode = mode }
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(
                        (labMode == mode ? KamikazeTheme.ion : .white).opacity(labMode == mode ? 0.3 : 0.06),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(.white.opacity(labMode == mode ? 0.32 : 0.1)))
            }
            .buttonStyle(.plain)
        }
    }

    private var sensorStatus: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 24) {
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
        GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
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
        GlassSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text(labMode == .guided
                    ? "STEP \(guidedIndex + 1) / \(guidedSteps.count)"
                    : "1 / CHOOSE YOUR INTENTION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                if labMode == .guided {
                    Text(guidedStep.trick.title)
                        .font(.system(size: 25, weight: .black, design: .rounded))
                    Text(guidedStep.condition.title)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.hazard)
                    Text(guidedStep.prompt)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    ProgressView(value: Double(guidedIndex + 1), total: Double(guidedSteps.count))
                        .tint(KamikazeTheme.volt)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(expectedTrickID.title)
                            .font(.system(size: 25, weight: .black, design: .rounded))
                        Spacer()
                        Text("\(selectedCaptureCount) SAVED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.volt)
                    }
                    Text(trickReadiness(expectedTrickID))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(trickNeedsEvidence(expectedTrickID)
                            ? KamikazeTheme.hazard
                            : KamikazeTheme.muted)
                    ForEach(trickShelves) { shelf in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(shelf.id)
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                Spacer()
                                Text(shelf.subtitle)
                                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                                    .multilineTextAlignment(.trailing)
                            }
                            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
                                ForEach(shelf.tricks, id: \.self) { trick in
                                    trickButton(trick)
                                }
                            }
                        }
                    }
                }
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

    private var selectedCaptureCount: Int {
        recorder.labelledDatasetExport?.countsByTrick[expectedTrickID, default: 0] ?? 0
    }

    private func trickButton(_ trick: DebugTrickID) -> some View {
        let selected = expectedTrickID == trick
        return Button {
            expectedTrickID = trick
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(rotationHint(trick))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(selected ? Color.black.opacity(0.65) : KamikazeTheme.muted)
                    Spacer()
                    if trickNeedsEvidence(trick) {
                        Circle()
                            .fill(selected ? Color.black.opacity(0.55) : KamikazeTheme.hazard)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(trick.title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(selected ? Color.black : KamikazeTheme.frost)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .bottomLeading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(
                selected ? KamikazeTheme.volt : .white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17)
                    .stroke(.white.opacity(selected ? 0.34 : 0.09))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select \(trick.title)")
    }

    private func trickNeedsEvidence(_ trick: DebugTrickID) -> Bool {
        switch trick {
        case .doubleFlip, .doubleReverseFlip, .doublePhoneFlip, .doubleReversePhoneFlip,
             .backsideShuvit, .frontsideShuvit:
            true
        default:
            false
        }
    }

    private func trickReadiness(_ trick: DebugTrickID) -> String {
        switch trick {
        case .unknown:
            "CONTROL LABEL · EXCLUDED FROM TRICK RECOGNITION"
        default:
            trickNeedsEvidence(trick)
                ? "COLLECT 3–5 CLEAN LANDED EXAMPLES + MISSES BEFORE DETECTION"
                : "AVAILABLE IN THE CURRENT PHYSICAL CATALOG"
        }
    }

    private func rotationHint(_ trick: DebugTrickID) -> String {
        switch trick {
        case .flip, .reverseFlip: "FLIP · 360°"
        case .doubleFlip, .doubleReverseFlip: "FLIP · 720°"
        case .phoneFlip, .reversePhoneFlip: "COMPOUND · ×1"
        case .doublePhoneFlip, .doubleReversePhoneFlip: "COMPOUND · ×2"
        case .backsideShuvit, .frontsideShuvit: "SHUV · 180°"
        case .backsideThreeSixtyShuvit, .frontsideThreeSixtyShuvit: "SHUV · 360°"
        case .straightAir: "AIR · 0°"
        case .unknown: "CONTROL"
        }
    }

    private func datasetCard(_ dataset: DebugSavedDatasetExport) -> some View {
        GlassSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("CLASSIFIED DATASET")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
                Text("\(dataset.captureCount) HUMAN-LABELLED CAPTURE\(dataset.captureCount == 1 ? "" : "S")")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                Text("Includes LANDED, MISSED and NO ATTEMPT. UNCLEAR stays on-device and is excluded.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                ShareLink(item: dataset.exportURL) {
                    Label("EXPORT CLASSIFIED DATASET", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
            }
            .padding(18)
        }
    }

    private func savedCard(_ saved: DebugSavedMotionCapture) -> some View {
        GlassSurface(cornerRadius: 24) {
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
        _outcome = State(initialValue: draft.proposedLabel.condition == .negativeControl ? .missed : .landed)
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
                        GlassSurface(role: .instrumentHUD, cornerRadius: 20) {
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
        GlassSurface(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                Text("2 / HUMAN LABEL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.volt)
                Picker("Intended trick", selection: $expectedTrickID) {
                    ForEach(DebugTrickID.allCases, id: \.self) { trick in
                        Text(trick.title).tag(trick)
                    }
                }
                Text("WHAT HAPPENED?")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
                    ForEach(DebugMotionCaptureOutcome.allCases.filter { $0 != .calibration }, id: \.self) { value in
                        selectionButton(value.title, selected: outcome == value) {
                            outcome = value
                        }
                    }
                }
                Text("THROW CONDITION")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 9) {
                    ForEach(DebugMotionCaptureCondition.allCases, id: \.self) { value in
                        selectionButton(value.title, selected: condition == value) {
                            condition = value
                        }
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

    private func selectionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(selected ? Color.black : KamikazeTheme.frost)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? KamikazeTheme.volt : .white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(selected ? 0.35 : 0.1)))
        }
        .buttonStyle(.plain)
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
