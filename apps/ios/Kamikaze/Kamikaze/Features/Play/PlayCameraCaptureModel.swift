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

    let screenVideoMaterial: VideoMaterial

    init() {
        let capture = CameraRunCaptureSession()
        self.capture = capture
        screenVideoMaterial = VideoMaterial(videoRenderer: capture.frontVideoRenderer)
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
                    outputURL: folder.appendingPathComponent("\(position.rawValue).mp4")
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

    func finishAttempt(attemptID: String, postRoll: Duration = .milliseconds(650)) async {
        guard isRecording else { return }
        try? await Task.sleep(for: postRoll)
        guard !Task.isCancelled else { return }

        capture.detachVideoRecorders()
        let finishing = recorders
        let takeID = activeTakeID ?? UUID().uuidString.lowercased()
        recorders.removeAll()
        activeTakeID = nil
        isRecording = false

        var artifacts: [CameraRunCameraPosition: CameraRunRecordingArtifact] = [:]
        for (position, recorder) in finishing {
            do {
                artifacts[position] = try await recorder.finish()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        guard !artifacts.isEmpty else { return }
        takesByAttemptID[attemptID] = PlayCameraTake(
            id: takeID,
            attemptID: attemptID,
            artifacts: artifacts,
            capturedWith: activeMode ?? .singleCamera
        )
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
        let deadline = clock.now + .seconds(3)
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
