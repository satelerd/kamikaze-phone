import AVFoundation
import SwiftUI
import UIKit

/// Device-facing product prototype for the Camera Run flow. Capture/export
/// infrastructure lives in Media; this screen makes the permission,
/// capability fallback and non-destructive edit contract tangible without
/// presenting unfinished media as a published feature.
struct CameraRunPrototypeView: View {
    private enum Step: String {
        case setup = "SETUP"
        case recording = "CAMERA RUN"
        case edit = "EDIT"
    }

    @State private var capture: CameraRunCaptureSession
    @State private var step: Step = .setup
    @State private var position: CameraRunCameraPosition = .rear
    @State private var wantsBothCameras = true
    @State private var caption = ""
    @State private var trimStart = 0.0
    @State private var trimEnd = 1.0
    @State private var layout: CameraRunLayoutPreset = .pictureInPicture
    @State private var errorMessage: String?

    init() {
        _capture = State(initialValue: CameraRunCaptureSession())
    }

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: step == .recording ? KamikazeTheme.hazard : KamikazeTheme.ion)
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
        .onDisappear { capture.stop() }
        .alert("Camera Run", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Camera unavailable")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CAMERA RUNS")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .tracking(-1.7)
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
        GlassSurface(role: .contentPanel, cornerRadius: 28) {
            ZStack(alignment: .topTrailing) {
                if isPrepared {
                    CameraRunPreview(session: capture.session)
                } else {
                    LinearGradient(
                        colors: [.black.opacity(0.2), KamikazeTheme.ion.opacity(0.18), .black.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 12) {
                        Image(systemName: "video.badge.ellipsis")
                            .font(.system(size: 42, weight: .medium))
                        Text(step == .edit ? "NON-DESTRUCTIVE DRAFT" : "CAMERA PREVIEW")
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
        }
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSurface(role: .instrumentHUD, cornerRadius: 22) {
                HStack {
                    Circle().fill(KamikazeTheme.hazard).frame(width: 10, height: 10)
                    rowTitle("CAMERA SESSION LIVE", detail: "Pre-talk → detected throw → post-talk will share one monotonic timeline after recorder wiring is validated on device.")
                    Spacer()
                    Text(capture.activeMode == .multiCamera ? "2 CAM" : "1 CAM")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.volt)
                }
                .padding(16)
            }
            Button {
                capture.stop()
                withAnimation(.snappy) { step = .edit }
            } label: {
                Text("OPEN EDIT PROTOTYPE")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 72)
            }
            .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.hazard)
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

            Button {
                errorMessage = "The edit contract and measured replay exporter are working. Dual-camera composition and Photos export remain device-validation gates in this prototype."
            } label: {
                Label("RENDER SHARE VIDEO", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 62)
            }
            .adaptiveGlassButton(prominent: true, tint: KamikazeTheme.volt)

            Button("NEW CAMERA RUN") {
                step = .setup
                errorMessage = nil
            }
            .font(.system(size: 11, weight: .black, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 48)
            .adaptiveGlassButton(tint: KamikazeTheme.ion)
        }
    }

    private var prototypeBoundary: some View {
        Text("PROTOTYPE · The live camera here validates permission and capability fallback; it does not yet save this preview. The measured replay exporter works separately. Nothing uploads automatically.")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(KamikazeTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
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

    private var stageBadge: String {
        switch capture.state {
        case .idle: "LOCAL · NOT RECORDING"
        case .requestingPermission: "REQUESTING CAMERA"
        case let .ready(mode, _), let .running(mode, _): mode == .multiCamera ? "FRONT + REAR" : "SINGLE CAMERA"
        case .interrupted: "INTERRUPTED"
        case .unavailable: "DEVICE GATE"
        case .failed: "CAMERA ERROR"
        }
    }

    private func prepareAndStart() {
        errorMessage = nil
        Task { @MainActor in
            do {
                _ = try await capture.prepare(
                    position: position,
                    mode: wantsBothCameras ? .multiCamera : .singleCamera
                )
                try capture.start()
                withAnimation(.snappy) { step = .recording }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CameraRunPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

private final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
