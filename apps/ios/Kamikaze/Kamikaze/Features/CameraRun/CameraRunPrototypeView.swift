import AVFoundation
import AVKit
import KamikazeMotionCore
import SwiftUI
import UIKit

struct CameraRunEditSeed {
    let result: NativeRunResult
    let take: PlayCameraTake
}

/// Device-facing product prototype for the Camera Run flow. Capture/export
/// infrastructure lives in Media; this screen makes the permission,
/// capability fallback and non-destructive edit contract tangible without
/// presenting unfinished media as a published feature.
struct CameraRunPrototypeView: View {
    private struct SavedCameraTrack: Identifiable {
        let position: CameraRunCameraPosition
        let artifact: CameraRunRecordingArtifact

        var id: URL { artifact.url }
    }

    private enum Step: String {
        case setup = "SETUP"
        case recording = "CAMERA RUN"
        case edit = "EDIT"
    }

    private enum RenderStyle: String, CaseIterable {
        case phoneReplay = "3D PHONE"
        case storyCut = "STORY CUT"

        var detail: String {
            switch self {
            case .phoneReplay:
                "One continuous clip: the saved front camera lives on the measured 3D phone for the full intro, throw and reaction."
            case .storyCut:
                "Camera intro, measured 3D during the throw, then camera again for the reaction."
            }
        }
    }

    private enum ExportFormat: String, CaseIterable {
        case vertical = "VERTICAL"
        case horizontal = "HORIZONTAL"

        var canvas: ReplayVideoCanvas {
            switch self {
            case .vertical: ReplayVideoCanvas(width: 720, height: 1_280)
            case .horizontal: ReplayVideoCanvas(width: 1_280, height: 720)
            }
        }
    }

    @State private var capture: CameraRunCaptureSession
    @State private var run = NativeRunModel()
    @State private var step: Step = .setup
    @State private var position: CameraRunCameraPosition = .rear
    @State private var wantsBothCameras = false
    @State private var caption = ""
    @State private var trimStart = 0.0
    @State private var trimEnd = 1.0
    @State private var layout: CameraRunLayoutPreset = .pictureInPicture
    @State private var replayEntry = 0.42
    @State private var replayResume = 0.68
    @State private var replayTransitionStyle: CameraRunReplayTransitionStyle = .crossDissolve
    @State private var replayTransitionDurationS = 0.25
    @State private var renderStyle: RenderStyle = .phoneReplay
    @State private var exportFormat: ExportFormat = .vertical
    @State private var slowMotionRate = 1.0
    @State private var errorMessage: String?
    @State private var recorders: [CameraRunCameraPosition: CameraRunVideoRecorder] = [:]
    @State private var savedTracks: [SavedCameraTrack] = []
    @State private var savedPreviewPlayer: AVPlayer?
    @State private var previewedTrackID: URL?
    @State private var renderedArtifact: CameraRunVideoCompositionArtifact?
    @State private var isFinalizing = false
    @State private var isPreparingPreview = false
    @State private var isRendering = false
    @State private var renderStage = "PREPARING"
    @State private var isSavingToPhotos = false
    @State private var seededResult: NativeRunResult?
    @Environment(AppearanceStore.self) private var appearance
    @Environment(\.dismiss) private var dismiss

    init(editSeed: CameraRunEditSeed? = nil) {
        _capture = State(initialValue: CameraRunCaptureSession())
        _seededResult = State(initialValue: editSeed?.result)
        if let editSeed {
            let tracks = editSeed.take.artifacts.map {
                SavedCameraTrack(position: $0.key, artifact: $0.value)
            }.sorted { $0.position.rawValue < $1.position.rawValue }
            _step = State(initialValue: .edit)
            _savedTracks = State(initialValue: tracks)
            if let first = tracks.first {
                _savedPreviewPlayer = State(initialValue: AVPlayer(url: first.artifact.url))
                _previewedTrackID = State(initialValue: first.id)
            }
        }
    }

    var body: some View {
        ZStack {
            ExperienceFieldBackground(
                ambient: step == .recording ? KamikazeTheme.hazard : KamikazeTheme.ion,
                externallyPaused: step == .edit || isRendering
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    cameraStage
                    switch step {
                    case .setup: setupControls
                    case .recording: recordingControls
                    case .edit: editorControls
                    }
                    prototypeBoundary
                }
                .padding(20)
                .padding(.bottom, 50)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if seededResult == nil {
                run.start()
                await preparePreview()
            }
        }
        .onChange(of: position) { _, _ in
            refreshPreviewForSetupChange()
        }
        .onChange(of: wantsBothCameras) { _, _ in
            refreshPreviewForSetupChange()
        }
        .onDisappear {
            run.stop()
            Task { @MainActor in
                if step == .recording {
                    await finishCameraRun(showEditor: false)
                } else {
                    await capture.stop()
                    capture.detachVideoRecorders()
                }
            }
        }
        .alert("Camera Run", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            if shouldOfferCameraSettings {
                Button("OPEN SETTINGS") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Camera unavailable")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text("CAMERA RUNS")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .tracking(-1.7)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))
                        .frame(width: 44, height: 44)
                }
                .adaptiveGlassButton()
                .accessibilityLabel("Back to result")
            }
            Text("TALK. THROW. CATCH. CUT IT YOUR WAY.")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.ion)
            HStack(spacing: 7) {
                ForEach([Step.setup, .recording, .edit], id: \.rawValue) { item in
                    Text(item.rawValue)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(item == step ? KamikazeTheme.pitch : KamikazeTheme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(item == step ? KamikazeTheme.volt : .white.opacity(0.06), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var cameraStage: some View {
        if step == .edit {
            // Liquid Glass composites *over* embedded AVKit controls. That
            // frosted the play button and scrubber even though taps still
            // worked. Media owns this clean black surface; glass remains on
            // the editor controls around it.
            cameraStageContent
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
        } else {
            GlassSurface(role: .contentPanel, cornerRadius: 28) {
                cameraStageContent
            }
        }
    }

    private var cameraStageContent: some View {
        ZStack(alignment: .topTrailing) {
            if isRendering {
                LinearGradient(
                    colors: [KamikazeTheme.pitch, KamikazeTheme.ion.opacity(0.22), KamikazeTheme.pitch],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 13) {
                    ProgressView()
                        .tint(KamikazeTheme.volt)
                        .controlSize(.large)
                    Text(renderStage)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.frost.opacity(0.8))
                }
            } else if step == .edit, let savedPreviewPlayer {
                VideoPlayer(player: savedPreviewPlayer)
                    .background(.black)
            } else if isPrepared {
                CameraRunPreview(previewLayer: capture.previewLayer)
            } else {
                LinearGradient(
                    colors: [.black.opacity(0.2), KamikazeTheme.ion.opacity(0.18), .black.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 12) {
                    if isPreparingPreview {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.15)
                    } else {
                        Image(systemName: "video.badge.ellipsis")
                    }
                    Text(stagePlaceholder)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.74))
            }

            Text(stageBadge)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(12)
        }
        .frame(height: 390)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var setupControls: some View {
        VStack(spacing: 12) {
            GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                VStack(spacing: 14) {
                    Toggle(isOn: $wantsBothCameras) {
                        rowTitle("FRONT + REAR", detail: "Falls back to one camera when the device or thermal state requires it.")
                    }
                    .tint(KamikazeTheme.volt)
                    Picker("Primary camera", selection: $position) {
                        Text("REAR").tag(CameraRunCameraPosition.rear)
                        Text("FRONT").tag(CameraRunCameraPosition.front)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16)
            }

            Button {
                prepareAndStart()
            } label: {
                Label("START CAMERA RUN", systemImage: "record.circle")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 66)
            }
            .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
            .disabled(isPreparingPreview)
        }
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                HStack {
                    Circle().fill(KamikazeTheme.hazard).frame(width: 10, height: 10)
                    rowTitle("RECORDING LOCALLY", detail: "Front and rear are written as separate MP4 tracks when MultiCam is available. Nothing is uploaded.")
                    Spacer()
                    Text(capture.activeMode == .multiCamera ? "2 CAM" : "1 CAM")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.volt)
                }
                .padding(16)
            }

            if let result = run.result {
                GlassSurface(role: .contentPanel, cornerRadius: 22) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(KamikazeTheme.volt)
                        rowTitle(
                            "\(result.displayName) CAPTURED",
                            detail: "Motion evidence is sealed. Keep talking, then finish when you want to edit the complete Camera Run."
                        )
                        Spacer()
                    }
                    .padding(16)
                }
            } else if run.canArm {
                Button {
                    run.arm()
                } label: {
                    Label("ARM THE THROW", systemImage: "gyroscope")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 62)
                }
                .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.ion)
            } else {
                GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                    HStack(spacing: 12) {
                        ProgressView().tint(KamikazeTheme.volt)
                        rowTitle(
                            motionPhaseTitle,
                            detail: "Throw once, catch it and hold it steady. Camera recording continues after detection."
                        )
                        Spacer()
                    }
                    .padding(16)
                }
            }

            Button {
                Task { @MainActor in
                    await finishCameraRun(showEditor: true)
                }
            } label: {
                if isFinalizing {
                    ProgressView()
                        .tint(KamikazeTheme.pitch)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    Text("FINISH + EDIT")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 72)
                }
            }
            .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.hazard)
            .disabled(isFinalizing)
        }
    }

    private var editorControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassSurface(role: .contentPanel, cornerRadius: 22) {
                VStack(alignment: .leading, spacing: 15) {
                    rowTitle("CUT THE RUN", detail: "Source clips stay untouched. These controls only describe the final vertical edit.")
                    TextField("Add a caption…", text: $caption)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    Picker("Layout", selection: $layout) {
                        Text("VERTICAL").tag(CameraRunLayoutPreset.vertical)
                        Text("PIP").tag(CameraRunLayoutPreset.pictureInPicture)
                    }
                    .pickerStyle(.segmented)

                    if !savedTracks.isEmpty {
                        Divider().overlay(.white.opacity(0.08))
                        VStack(alignment: .leading, spacing: 9) {
                            Text("SAVED SOURCE TRACKS")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.volt)
                            ForEach(savedTracks) { track in
                                HStack(spacing: 10) {
                                    Button {
                                        showSavedTrack(track)
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: previewedTrackID == track.id ? "play.rectangle.fill" : "play.rectangle")
                                                .foregroundStyle(previewedTrackID == track.id ? KamikazeTheme.volt : KamikazeTheme.ion)
                                            Label(
                                                "PREVIEW \(track.position.rawValue.uppercased())",
                                                systemImage: track.position == .front ? "person.crop.rectangle" : "camera"
                                            )
                                            Spacer()
                                            Text("\(track.artifact.frameCount)F · \(track.artifact.durationS, format: .number.precision(.fractionLength(1)))S")
                                                .foregroundStyle(KamikazeTheme.muted)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    ShareLink(item: track.artifact.url) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 15, weight: .bold))
                                            .frame(width: 42, height: 42)
                                            .background(.white.opacity(0.06), in: Circle())
                                    }
                                    .accessibilityLabel("Share \(track.position.rawValue) camera MP4")
                                }
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .frame(minHeight: 44)
                            }
                        }
                    }
                    VStack(spacing: 4) {
                        HStack {
                            Text("IN  \(Int(trimStart * 100))%")
                            Spacer()
                            Text("OUT  \(Int(trimEnd * 100))%")
                        }
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                        Slider(value: $trimStart, in: 0...max(0, trimEnd - 0.05))
                            .tint(KamikazeTheme.ion)
                        Slider(value: $trimEnd, in: min(1, trimStart + 0.05)...1)
                            .tint(KamikazeTheme.volt)
                    }
                }
                .padding(16)
            }

            if let result = editingResult, !isRendering {
                CameraRunMeasuredReplayCard(result: result, take: editingTake)
                renderStyleControls
                if renderStyle == .storyCut {
                    replayStoryCutControls
                }
            }

            Button {
                Task { @MainActor in
                    await renderFinalVideo()
                }
            } label: {
                if isRendering {
                    HStack(spacing: 10) {
                        ProgressView().tint(KamikazeTheme.pitch)
                        Text(renderStage)
                    }
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 62)
                } else {
                    Label(
                        renderButtonTitle,
                        systemImage: "wand.and.stars.inverse"
                    )
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
            }
            .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)
            .disabled(isRendering || savedTracks.isEmpty)

            if let renderedArtifact {
                GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        rowTitle(
                            "FINAL VIDEO READY",
                            detail: "\(String(format: "%.1f", renderedArtifact.durationS)) seconds · vertical MP4 · original camera sources preserved."
                        )
                        HStack(spacing: 10) {
                            ShareLink(item: renderedArtifact.url) {
                                Label("SHARE", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .adaptiveGlassButton(tint: KamikazeTheme.ion)

                            Button {
                                Task { @MainActor in
                                    await saveRenderedVideoToPhotos()
                                }
                            } label: {
                                if isSavingToPhotos {
                                    ProgressView().frame(maxWidth: .infinity, minHeight: 48)
                                } else {
                                    Label("SAVE", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                }
                            }
                            .adaptiveGlassButton(tint: KamikazeTheme.volt)
                            .disabled(isSavingToPhotos)
                        }
                        .font(.system(size: 10, weight: .black, design: .rounded))
                    }
                    .padding(16)
                }
            }

            Button("NEW CAMERA RUN") {
                savedPreviewPlayer?.pause()
                savedPreviewPlayer = nil
                previewedTrackID = nil
                step = .setup
                errorMessage = nil
                savedTracks = []
                renderedArtifact = nil
                seededResult = nil
                run.start()
                run.dismissResult()
                replayEntry = 0.42
                replayResume = 0.68
                replayTransitionStyle = .crossDissolve
                replayTransitionDurationS = 0.25
                renderStyle = .phoneReplay
                slowMotionRate = 1
                Task { @MainActor in await preparePreview() }
            }
            .font(.system(size: 11, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 48)
            .adaptiveGlassButton(tint: KamikazeTheme.ion)
        }
    }

    private var prototypeBoundary: some View {
        Text("BETA · Front/rear clips stay untouched while exports use measured motion. Camera runs request the microphone and preserve its real audio when permission is granted. Nothing uploads automatically.")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(KamikazeTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var replayStoryCutControls: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 15) {
                rowTitle(
                    "STORY CUT",
                    detail: "Keep your intro, replace the throw window with measured 3D, then return to the camera for the reaction. Sources stay untouched."
                )

                CameraRunStoryTimelinePreview(
                    replayEntry: replayEntry,
                    replayResume: replayResume
                )

                Picker("Transition", selection: $replayTransitionStyle) {
                    Text("CUT").tag(CameraRunReplayTransitionStyle.cut)
                    Text("DISSOLVE").tag(CameraRunReplayTransitionStyle.crossDissolve)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 5) {
                    HStack {
                        Text("3D IN  \(Int(replayEntry * 100))%")
                        Spacer()
                        Text("CAMERA BACK  \(Int(replayResume * 100))%")
                    }
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                    Slider(value: $replayEntry, in: 0...max(0, replayResume - 0.05))
                        .tint(KamikazeTheme.ion)
                    Slider(value: $replayResume, in: min(1, replayEntry + 0.05)...1)
                        .tint(KamikazeTheme.volt)
                }

                if replayTransitionStyle == .crossDissolve {
                    VStack(spacing: 5) {
                        HStack {
                            Text("DISSOLVE")
                            Spacer()
                            Text("\(replayTransitionDurationS, format: .number.precision(.fractionLength(2)))S")
                        }
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                        Slider(value: $replayTransitionDurationS, in: 0.10...0.60)
                            .tint(KamikazeTheme.volt)
                    }
                }
            }
            .padding(16)
        }
    }

    private var renderStyleControls: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                rowTitle("EXPORT STYLE", detail: renderStyle.detail)
                Picker("Export style", selection: $renderStyle) {
                    ForEach(RenderStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading, spacing: 7) {
                    rowTitle(
                        "TRICK SPEED",
                        detail: slowMotionRate < 1
                            ? "Intro and reaction stay at 1x. Only the measured motion window slows down."
                            : "The complete clip plays at its original speed."
                    )
                    Picker("Trick speed", selection: $slowMotionRate) {
                        Text("1×").tag(1.0)
                        Text("0.5×").tag(0.5)
                        Text("0.35×").tag(0.35)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(16)
        }
        .onChange(of: renderStyle) { _, _ in
            renderedArtifact = nil
        }
        .onChange(of: exportFormat) { _, _ in
            renderedArtifact = nil
        }
        .onChange(of: slowMotionRate) { _, _ in
            renderedArtifact = nil
        }
    }

    private var renderButtonTitle: String {
        if renderedArtifact != nil { return "RENDER CHANGES" }
        if editingResult == nil { return "RENDER CAMERA VIDEO" }
        return renderStyle == .phoneReplay
            ? "RENDER 3D PHONE VIDEO"
            : "RENDER STORY CUT"
    }

    private func rowTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .black, design: .rounded))
            Text(detail)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isPrepared: Bool {
        switch capture.state {
        case .ready, .running: true
        default: false
        }
    }

    private var editingResult: NativeRunResult? {
        seededResult ?? run.result
    }

    private var editingTake: PlayCameraTake? {
        guard let result = editingResult, !savedTracks.isEmpty else { return nil }
        let artifacts = Dictionary(uniqueKeysWithValues: savedTracks.map { ($0.position, $0.artifact) })
        return PlayCameraTake(
            id: "camera-editor-\(result.id)",
            attemptID: result.id,
            artifacts: artifacts,
            capturedWith: artifacts.count > 1 ? .multiCamera : .singleCamera
        )
    }

    private var stageBadge: String {
        if step == .recording, run.result != nil { return "MOTION CAPTURED" }
        return switch capture.state {
        case .idle: "LOCAL · NOT RECORDING"
        case .requestingPermission: "REQUESTING CAMERA"
        case let .ready(mode, _), let .running(mode, _): mode == .multiCamera ? "FRONT + REAR" : "SINGLE CAMERA"
        case .interrupted: "INTERRUPTED"
        case .unavailable: "DEVICE GATE"
        case .failed: "CAMERA ERROR"
        }
    }

    private var motionPhaseTitle: String {
        switch run.phase {
        case .armed: "WAITING FOR THROW"
        case .motion: "TRICK IN MOTION"
        case .settling: "HOLD THE CATCH"
        case .failed: "MOTION ERROR"
        case .ready, .result, .unknown: "MOTION READY"
        }
    }

    private var stagePlaceholder: String {
        if step == .edit { return "NON-DESTRUCTIVE DRAFT" }
        switch capture.state {
        case .requestingPermission:
            return "ALLOW CAMERA ACCESS"
        case .unavailable:
            return "CAMERA ACCESS NEEDED"
        case .failed:
            return "CAMERA COULD NOT START"
        default:
            return "STARTING CAMERA"
        }
    }

    private var shouldOfferCameraSettings: Bool {
        switch capture.state {
        case .unavailable(.permissionDenied), .unavailable(.permissionRestricted):
            return true
        default:
            return false
        }
    }

    private func prepareAndStart() {
        errorMessage = nil
        Task { @MainActor in
            guard await preparePreview() else { return }
            do {
                let gate = CameraRunStartGate(
                    isPreparingPreview: isPreparingPreview,
                    isSessionRunning: capture.isRunning,
                    activeMode: capture.activeMode
                )
                guard gate.canAttachRecorders else {
                    throw CameraRunCaptureError.configurationFailed("The camera preview is not ready.")
                }
                guard let activeMode = capture.activeMode else {
                    throw CameraRunCaptureError.configurationFailed("The camera preview is not ready.")
                }
                try startRecorders(for: activeMode)
                withAnimation(.snappy) { step = .recording }
            } catch {
                capture.detachVideoRecorders()
                recorders.removeAll()
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Camera access and the live preview are prepared as soon as this mode
    /// appears. Starting a run only attaches local recorders; it does not tear
    /// down and rebuild the capture graph underneath the preview.
    @MainActor
    @discardableResult
    private func preparePreview() async -> Bool {
        guard step == .setup else { return capture.isRunning }
        if capture.isRunning, !isPreparingPreview { return true }
        guard !isPreparingPreview else { return false }

        isPreparingPreview = true
        defer { isPreparingPreview = false }
        errorMessage = nil

        do {
            await capture.stop()
            _ = try await capture.prepare(
                position: position,
                mode: wantsBothCameras ? .multiCamera : .singleCamera
            )
            guard !Task.isCancelled else {
                await capture.stop()
                return false
            }
            try await capture.start()
            return true
        } catch {
            await capture.stop()
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func refreshPreviewForSetupChange() {
        guard step == .setup, !isPreparingPreview else { return }
        Task { @MainActor in
            await capture.stop()
            await preparePreview()
        }
    }

    private func startRecorders(for mode: CameraRunCaptureMode) throws {
        let positions: [CameraRunCameraPosition]
        if mode == .multiCamera {
            positions = [.front, .rear]
        } else {
            positions = [capture.activePosition ?? position]
        }

        let runDirectory = URL.applicationSupportDirectory
            .appending(path: "CameraRuns", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        var started: [CameraRunCameraPosition: CameraRunVideoRecorder] = [:]

        for cameraPosition in positions {
            let outputURL = runDirectory.appending(path: "\(cameraPosition.rawValue).mp4")
            let recorder = CameraRunVideoRecorder(outputURL: outputURL, position: cameraPosition)
            try recorder.start()
            capture.attachVideoRecorder(recorder, for: cameraPosition)
            started[cameraPosition] = recorder
        }
        recorders = started
    }

    @MainActor
    private func finishCameraRun(showEditor: Bool) async {
        if run.result == nil {
            run.cancel()
        }
        guard !recorders.isEmpty, !isFinalizing else {
            await capture.stop()
            if showEditor { withAnimation(.snappy) { step = .edit } }
            return
        }

        await capture.stop()
        capture.detachVideoRecorders()
        let pending = recorders
        recorders.removeAll()
        isFinalizing = true

        Task { @MainActor in
            var completed: [SavedCameraTrack] = []
            var failures: [String] = []
            for (cameraPosition, recorder) in pending {
                do {
                    let artifact = try await recorder.finish()
                    completed.append(SavedCameraTrack(position: cameraPosition, artifact: artifact))
                } catch {
                    failures.append("\(cameraPosition.rawValue): \(error.localizedDescription)")
                }
            }
            savedTracks = completed.sorted { $0.position.rawValue < $1.position.rawValue }
            if let firstTrack = savedTracks.first {
                showSavedTrack(firstTrack)
            }
            isFinalizing = false
            if showEditor {
                withAnimation(.snappy) { step = .edit }
            }
            if !failures.isEmpty {
                errorMessage = completed.isEmpty
                    ? "No camera track could be saved. \(failures.joined(separator: " · "))"
                    : "Some camera tracks could not be saved. \(failures.joined(separator: " · "))"
            }
        }
    }

    private func showSavedTrack(_ track: SavedCameraTrack) {
        savedPreviewPlayer?.pause()
        savedPreviewPlayer = AVPlayer(url: track.artifact.url)
        previewedTrackID = track.id
    }

    @MainActor
    private func renderFinalVideo() async {
        guard !savedTracks.isEmpty, !isRendering else { return }
        let previousIdleTimerState = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdleTimerState }
        savedPreviewPlayer?.pause()
        renderStage = "CLEARING LIVE PREVIEW"
        isRendering = true
        defer { isRendering = false }
        errorMessage = nil

        // Unmount the interactive RealityKit replay and VideoPlayer before
        // asking AVFoundation/VideoToolbox for a second off-screen pipeline.
        // This mirrors the resource isolation that made Result replay smooth.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        let sourceDuration = savedTracks.map(\.artifact.durationS).min() ?? 0
        guard sourceDuration > 0 else {
            errorMessage = CameraRunVideoCompositionError.invalidDuration.localizedDescription
            return
        }
        let boundedStart = min(trimStart, max(0, trimEnd - 0.05))
        let boundedEnd = max(trimEnd, min(1, boundedStart + 0.05))
        let trim = CameraRunTrim(
            startS: sourceDuration * boundedStart,
            endS: sourceDuration * boundedEnd
        )
        let captions: [CameraRunCaption]
        let cleanCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanCaption.isEmpty {
            captions = []
        } else {
            captions = [CameraRunCaption(
                text: cleanCaption,
                startS: trim.startS,
                endS: trim.endS,
                placement: .bottom
            )]
        }

        let outputDirectory = URL.applicationSupportDirectory
            .appending(path: "CameraRuns", directoryHint: .isDirectory)
            .appending(path: "Exports", directoryHint: .isDirectory)
        let exportID = UUID().uuidString
        let wantsSpeedRamp = slowMotionRate < 0.999 && editingResult != nil
        let finalOutputURL = outputDirectory.appending(path: "kamikaze-camera-run-\(exportID).mp4")
        let baseOutputURL = wantsSpeedRamp
            ? outputDirectory.appending(path: "normal-speed-\(exportID).mp4")
            : finalOutputURL
        do {
            let composer = CameraRunVideoComposer()
            var artifact: CameraRunVideoCompositionArtifact
            var speedRampRange: CameraRunTrim?

            if let result = editingResult, renderStyle == .phoneReplay {
                guard let screenTrack = savedTracks.first(where: { $0.position == .front })
                    ?? savedTracks.first else {
                    throw CameraRunVideoCompositionError.noSources
                }
                let motionFrames = ReplayBuilder.normalized(ReplayBuilder.buildFrames(
                    payload: result.capture.samplePayload,
                    boundaries: result.capture.attempt.boundaries
                ))
                let fullTakeFrames = CameraReplayTiming.fullTakeFrames(
                    motionFrames: motionFrames,
                    motionCaptureStartS: result.capture.attempt.boundaries.captureStartS,
                    artifact: screenTrack.artifact
                )
                let boundaries = result.capture.attempt.boundaries
                let replayDurationS = max(0, boundaries.captureEndS - boundaries.captureStartS)
                let captureStartOnTakeS = CameraReplayTiming.videoTime(
                    replayTimeS: 0,
                    replayDurationS: replayDurationS,
                    motionCaptureStartS: boundaries.captureStartS,
                    artifact: screenTrack.artifact
                )
                speedRampRange = CameraRunTrim(
                    startS: captureStartOnTakeS + boundaries.motionStartS - boundaries.captureStartS - trim.startS,
                    endS: captureStartOnTakeS + boundaries.motionEndS - boundaries.captureStartS - trim.startS
                ).clamped(to: trim.durationS)
                let canvas = exportFormat.canvas
                let silentOutputURL = outputDirectory.appending(path: "silent-phone-\(exportID).mp4")
                let replayRequest = ReplayVideoExportRequest(
                    frames: fullTakeFrames,
                    edit: CameraRunEdit(trim: trim, captions: captions),
                    outputURL: silentOutputURL,
                    canvas: canvas,
                    frameRate: 30
                )
                renderStage = "RENDERING FULL 3D PHONE"
                let replayArtifact = try await ReplayVideoExporter().export(
                    replayRequest,
                    renderer: RealityKitReplayFrameRenderer(
                        appearance: appearance.effective,
                        accent: UIColor(KamikazeTheme.volt),
                        screenVideoURL: screenTrack.artifact.url,
                        screenVideoOffsetS: 0,
                        branding: ReplayVideoBranding(
                            trickName: result.displayName,
                            score: result.evaluation.score?.value
                        )
                    ),
                    progress: { completed, total in
                        renderStage = "RENDERING 3D  ·  \(completed) / \(total) FRAMES"
                    }
                )
                renderStage = "ADDING MICROPHONE"
                artifact = try await composer.attachAudio(
                    videoURL: replayArtifact.url,
                    audioSourceURL: screenTrack.artifact.url,
                    audioStartS: trim.startS,
                    outputURL: baseOutputURL,
                    canvas: CGSize(
                        width: CGFloat(replayArtifact.canvas.width),
                        height: CGFloat(replayArtifact.canvas.height)
                    )
                )
                try? FileManager.default.removeItem(at: replayArtifact.url)
            } else {
                let cameraOutputURL = editingResult == nil
                    ? finalOutputURL
                    : outputDirectory.appending(path: "camera-cut-\(exportID).mp4")
                let request = CameraRunVideoCompositionRequest(
                    sources: savedTracks.map {
                        CameraRunVideoSource(position: $0.position, url: $0.artifact.url)
                    },
                    edit: CameraRunEdit(
                        trim: trim,
                        layout: CameraRunLayout(
                            preset: layout,
                            width: exportFormat.canvas.width,
                            height: exportFormat.canvas.height
                        ),
                        captions: captions
                    ),
                    outputURL: cameraOutputURL
                )
                renderStage = "COMPOSING CAMERA TRACKS"
                let cameraArtifact = try await composer.export(request)

                if let result = editingResult {
                    let replayURL = outputDirectory.appending(path: "measured-replay-\(exportID).mp4")
                    let replayRequest = ReplayVideoExportRequest(
                        capture: result.capture,
                        outputURL: replayURL,
                        canvas: exportFormat.canvas,
                        frameRate: 30
                    )
                    renderStage = "RENDERING MEASURED 3D"
                    let frontTrack = savedTracks.first { $0.position == .front }
                    let videoOffsetS = frontTrack?.artifact.sourceStartTimestampS.map {
                        max(0, result.capture.attempt.boundaries.captureStartS - $0)
                    } ?? 0
                    let replayArtifact = try await ReplayVideoExporter().export(
                        replayRequest,
                        renderer: RealityKitReplayFrameRenderer(
                            appearance: appearance.effective,
                            accent: UIColor(KamikazeTheme.volt),
                            screenVideoURL: frontTrack?.artifact.url,
                            screenVideoOffsetS: videoOffsetS,
                            branding: ReplayVideoBranding(
                                trickName: result.displayName,
                                score: result.evaluation.score?.value
                            )
                        ),
                        progress: { completed, total in
                            renderStage = "RENDERING 3D  ·  \(completed) / \(total) FRAMES"
                        }
                    )
                    renderStage = "BUILDING STORY CUT"
                    let transition = CameraRunReplayTransition(
                        entryProgress: replayEntry,
                        resumeProgress: replayResume,
                        style: replayTransitionStyle,
                        durationS: replayTransitionDurationS
                    )
                    let storyPlan = try CameraRunReplayTimelinePlan.make(
                        cameraDurationS: cameraArtifact.durationS,
                        replayDurationS: replayArtifact.durationS,
                        transition: transition
                    )
                    let boundaries = result.capture.attempt.boundaries
                    speedRampRange = CameraRunTrim(
                        startS: storyPlan.replayStartS + boundaries.motionStartS - boundaries.captureStartS,
                        endS: storyPlan.replayStartS + boundaries.motionEndS - boundaries.captureStartS
                    ).clamped(to: storyPlan.outputDurationS)
                    artifact = try await composer.composeReplay(
                        cameraArtifact: cameraArtifact,
                        replayArtifact: replayArtifact,
                        transition: transition,
                        outputURL: baseOutputURL
                    )
                    try? FileManager.default.removeItem(at: cameraArtifact.url)
                    try? FileManager.default.removeItem(at: replayArtifact.url)
                } else {
                    artifact = cameraArtifact
                }
            }
            if wantsSpeedRamp, let speedRampRange {
                renderStage = "SLOWING THE TRICK  ·  \(String(format: "%.2g", slowMotionRate))×"
                let normalSpeedArtifact = artifact
                artifact = try await composer.applySpeedRamp(
                    to: normalSpeedArtifact,
                    sourceRange: speedRampRange,
                    playbackRate: slowMotionRate,
                    outputURL: finalOutputURL
                )
                try? FileManager.default.removeItem(at: normalSpeedArtifact.url)
            }
            renderedArtifact = artifact
            savedPreviewPlayer?.pause()
            savedPreviewPlayer = AVPlayer(url: artifact.url)
            previewedTrackID = artifact.url
            savedPreviewPlayer?.play()
            renderStage = "VIDEO READY"
        } catch {
            errorMessage = "[\(renderStage)] \(error.localizedDescription)"
        }
    }

    @MainActor
    private func saveRenderedVideoToPhotos() async {
        guard let renderedArtifact, !isSavingToPhotos else { return }
        isSavingToPhotos = true
        defer { isSavingToPhotos = false }
        do {
            try await CameraRunVideoComposer().saveToPhotos(renderedArtifact)
            errorMessage = "Saved the finished Camera Run to Photos."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CameraRunStoryTimelinePreview: View {
    let replayEntry: Double
    let replayResume: Double

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width - 6)
            let entry = min(1, max(0, replayEntry))
            let resume = min(1, max(entry, replayResume))
            HStack(spacing: 3) {
                timelineSegment(
                    "CAM",
                    color: KamikazeTheme.ion,
                    foreground: .white,
                    width: width * entry
                )
                timelineSegment(
                    "3D",
                    color: KamikazeTheme.volt,
                    foreground: KamikazeTheme.pitch,
                    width: width * (resume - entry)
                )
                timelineSegment(
                    "BACK",
                    color: KamikazeTheme.hazard,
                    foreground: .white,
                    width: width * (1 - resume)
                )
            }
        }
        .frame(height: 34)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Camera until \(Int(replayEntry * 100)) percent, measured replay, then camera returns at \(Int(replayResume * 100)) percent"
        )
    }

    private func timelineSegment(
        _ label: String,
        color: Color,
        foreground: Color,
        width: CGFloat
    ) -> some View {
        Text(label)
            .font(.system(size: 7, weight: .black, design: .monospaced))
            .foregroundStyle(foreground)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(color.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CameraRunMeasuredReplayCard: View {
    let result: NativeRunResult
    let take: PlayCameraTake?
    let freefall: FreefallWindow?
    let videoTimelineOffsetS: Double?
    @State private var replay: ReplayController

    init(result: NativeRunResult, take: PlayCameraTake?) {
        self.result = result
        self.take = take
        let motionFrames = ReplayBuilder.normalized(ReplayBuilder.buildFrames(
            payload: result.capture.samplePayload,
            boundaries: result.capture.attempt.boundaries
        ))
        let frames: [ReplayFrame]
        if let artifact = take?.front {
            frames = CameraReplayTiming.fullTakeFrames(
                motionFrames: motionFrames,
                motionCaptureStartS: result.capture.attempt.boundaries.captureStartS,
                artifact: artifact
            )
            videoTimelineOffsetS = 0
            // The editor timeline includes non-motion time. Keep the phone at
            // origin rather than fabricating an arc across the introduction.
            freefall = nil
        } else {
            frames = motionFrames
            videoTimelineOffsetS = nil
            freefall = ReplayBuilder.freefallWindow(in: frames)
        }
        _replay = State(initialValue: ReplayController(frames: frames))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(take?.front == nil
                 ? "MEASURED TRICK REPLAY  /  \(result.displayName)"
                 : "FULL TAKE  /  INTRO · \(result.displayName) · REACTION")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.volt)
            CameraReplayPhoneView(
                controller: replay,
                accent: KamikazeTheme.volt,
                arcWindow: freefall,
                take: take,
                motionCaptureStartS: result.capture.attempt.boundaries.captureStartS,
                videoTimelineOffsetS: videoTimelineOffsetS
            )
        }
        .onAppear { replay.play() }
        .onDisappear { replay.pause() }
    }
}

private struct CameraRunPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.install(previewLayer)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.install(previewLayer)
    }
}

private final class CameraPreviewUIView: UIView {
    private weak var installedLayer: AVCaptureVideoPreviewLayer?

    func install(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard installedLayer !== previewLayer else { return }
        installedLayer?.removeFromSuperlayer()
        layer.addSublayer(previewLayer)
        installedLayer = previewLayer
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        installedLayer?.frame = bounds
    }
}
