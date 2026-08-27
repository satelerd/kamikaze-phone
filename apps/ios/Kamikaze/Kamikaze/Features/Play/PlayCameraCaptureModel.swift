import Foundation
import Observation
import RealityKit
@preconcurrency import AVFoundation

nonisolated struct PlayCameraTake: Identifiable, Sendable {
    let id: String
    let attemptID: String
    let artifacts: [CameraRunCameraPosition: CameraRunRecordingArtifact]
    let capturedWith: CameraRunCaptureMode

    var front: CameraRunRecordingArtifact? { artifacts[.front] }
    var rear: CameraRunRecordingArtifact? { artifacts[.rear] }
    var cameraCount: Int { artifacts.count }
}

/// Camera V2 is an optional capability of Play, not a separate game mode.
/// The capture graph stays warm while enabled, each detected attempt receives
/// its own immutable front/rear source clips, and the front sample stream also
/// drives the live RealityKit phone screen.
@MainActor
@Observable
final class PlayCameraCaptureModel {
    @ObservationIgnored private let capture: CameraRunCaptureSession
    @ObservationIgnored private var recorders: [CameraRunCameraPosition: CameraRunVideoRecorder] = [:]
    @ObservationIgnored private var activeTakeID: String?

    private(set) var isEnabled = false
    private(set) var isPreparing = false
    private(set) var isRecording = false
    private(set) var activeMode: CameraRunCaptureMode?
    private(set) var errorMessage: String?
    private(set) var takesByAttemptID: [String: PlayCameraTake] = [:]
    /// A result must never wait forever for a camera artifact. Successful and
    /// failed writer completions both seal an attempt; the latter simply
    /// falls back to the sensor-only result and exposes `errorMessage`.
    private(set) var sealedAttemptIDs: Set<String> = []

    let screenVideoMaterial: VideoMaterial

    init() {
        let capture = CameraRunCaptureSession()
        self.capture = capture
        var screenVideoMaterial = VideoMaterial(videoRenderer: capture.frontVideoRenderer)
        // Imported display meshes do not share one winding convention. The
        // selfie feed is a screen, not an opaque shell, so it must render from
        // whichever side the asset authors chose as its front face.
        screenVideoMaterial.faceCulling = .none
        self.screenVideoMaterial = screenVideoMaterial
    }

    var statusLabel: String {
        if isPreparing { return "CAMERA STARTING" }
        if isRecording { return activeMode == .multiCamera ? "REC · FRONT + REAR" : "REC · FRONT" }
        if isEnabled { return activeMode == .multiCamera ? "FRONT + REAR READY" : "FRONT CAMERA READY" }
        return "CAMERA OFF"
    }

    func take(for attemptID: String) -> PlayCameraTake? {
        takesByAttemptID[attemptID]
    }

    func isAttemptSealed(_ attemptID: String) -> Bool {
        sealedAttemptIDs.contains(attemptID)
    }

    func toggle() async {
        if isEnabled || isPreparing {
            await disable()
        } else {
            await enable()
        }
    }

    func enable() async {
        guard !isEnabled, !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        do {
            let mode = try await capture.prepare(position: .front, mode: .multiCamera)
            try await capture.start()
            activeMode = mode
            isEnabled = true
        } catch {
            activeMode = nil
            isEnabled = false
            errorMessage = error.localizedDescription
        }
        isPreparing = false
    }

    /// Must complete before motion capture arms so the camera clip always
    /// contains the complete evidence window rather than joining mid-throw.
    func beginAttempt() async -> Bool {
        guard isEnabled else { return true }
        guard !isRecording else { return true }
        if !capture.isRunning {
            do {
                try await capture.start()
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }

        let takeID = UUID().uuidString.lowercased()
        do {
            let positions: [CameraRunCameraPosition] = activeMode == .multiCamera
                ? [.front, .rear]
                : [capture.activePosition ?? .front]
            let folder = try takeFolder(id: takeID)
            var pending: [CameraRunCameraPosition: CameraRunVideoRecorder] = [:]
            for position in positions {
                let recorder = CameraRunVideoRecorder(
                    outputURL: folder.appendingPathComponent("\(position.rawValue).mp4"),
                    position: position
                )
                try recorder.start()
                pending[position] = recorder
                capture.attachVideoRecorder(recorder, for: position)
            }
            recorders = pending
            activeTakeID = takeID
            isRecording = true
            errorMessage = nil
            return true
        } catch {
            capture.detachVideoRecorders()
            recorders.removeAll()
            activeTakeID = nil
            isRecording = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Keep recording after detection so the source take includes the human
    /// reaction. The immediate Result remains trick-focused; the editor owns
    /// this longer intro/trick/reaction timeline.
    func finishAttempt(attemptID: String, postRoll: Duration = .milliseconds(2_500)) async {
        guard isRecording else {
            sealedAttemptIDs.insert(attemptID)
            return
        }
        try? await Task.sleep(for: postRoll)
        guard !Task.isCancelled else {
            sealedAttemptIDs.insert(attemptID)
            return
        }

        capture.detachVideoRecorders()
        let finishing = recorders
        let takeID = activeTakeID ?? UUID().uuidString.lowercased()
        recorders.removeAll()
        activeTakeID = nil
        isRecording = false

        // The result owns a separate RealityView + AVPlayer. Stop the live
        // dual-camera graph and flush its sample renderer before creating
        // that decoder; keeping both active caused a reproducible resource
        // spike during SEALING CAMERA on physical devices. beginAttempt()
        // starts this already-configured graph again for the next throw.
        await capture.stop()
        capture.frontVideoRenderer.flush()

        var artifacts: [CameraRunCameraPosition: CameraRunRecordingArtifact] = [:]
        for (position, recorder) in finishing {
            do {
                artifacts[position] = try await recorder.finish()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if !artifacts.isEmpty {
            takesByAttemptID[attemptID] = PlayCameraTake(
                id: takeID,
                attemptID: attemptID,
                artifacts: artifacts,
                capturedWith: activeMode ?? .singleCamera
            )
        }
        sealedAttemptIDs.insert(attemptID)
    }

    func abandonAttempt() async {
        guard isRecording else { return }
        capture.detachVideoRecorders()
        let abandoned = recorders
        recorders.removeAll()
        activeTakeID = nil
        isRecording = false
        for (_, recorder) in abandoned {
            if let artifact = try? await recorder.finish() {
                try? FileManager.default.removeItem(at: artifact.url)
            }
        }
    }

    func waitUntilAttemptIsSealed() async {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(6)
        while isRecording, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    func disable() async {
        if isRecording { await abandonAttempt() }
        capture.detachVideoRecorders()
        await capture.stop()
        capture.frontVideoRenderer.flush()
        isEnabled = false
        isPreparing = false
        activeMode = nil
    }

    func shutdown() async {
        await disable()
    }

    private func takeFolder(id: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base
            .appendingPathComponent("CameraV2", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
