import Foundation
import Observation
import OSLog
@preconcurrency import AVFoundation

nonisolated public enum CameraRunCameraPosition: String, Codable, CaseIterable, Equatable, Sendable {
    case front
    case rear

    fileprivate var avPosition: AVCaptureDevice.Position {
        switch self {
        case .front: .front
        case .rear: .back
        }
    }
}

nonisolated public enum CameraRunCaptureMode: String, Codable, Equatable, Sendable {
    case singleCamera
    case multiCamera
}

nonisolated public struct CameraRunCaptureCapabilities: Codable, Equatable, Sendable {
    public let hasFrontCamera: Bool
    public let hasRearCamera: Bool
    public let supportsMultiCamera: Bool

    public init(
        hasFrontCamera: Bool,
        hasRearCamera: Bool,
        supportsMultiCamera: Bool
    ) {
        self.hasFrontCamera = hasFrontCamera
        self.hasRearCamera = hasRearCamera
        self.supportsMultiCamera = supportsMultiCamera
    }

    public var hasAnyCamera: Bool { hasFrontCamera || hasRearCamera }
}

nonisolated public enum CameraRunCaptureError: Error, Codable, Equatable, LocalizedError, Sendable {
    case simulatorUnavailable
    case cameraUnavailable
    case requiredPositionUnavailable(CameraRunCameraPosition)
    case permissionDenied
    case permissionRestricted
    case configurationFailed(String)
    case interrupted(String)
    case runtime(String)
    case noVideoFrames

    public var errorDescription: String? {
        switch self {
        case .simulatorUnavailable:
            "Camera capture is unavailable in the iOS Simulator."
        case .cameraUnavailable:
            "No compatible camera is available on this device."
        case let .requiredPositionUnavailable(position):
            "The \(position.rawValue) camera is unavailable on this device."
        case .permissionDenied:
            "Camera permission is denied. Enable it in Settings to record a Camera Run."
        case .permissionRestricted:
            "Camera access is restricted on this device."
        case let .configurationFailed(reason):
            "Camera configuration failed: \(reason)"
        case let .interrupted(reason):
            "Camera capture was interrupted: \(reason)"
        case let .runtime(reason):
            "Camera capture stopped: \(reason)"
        case .noVideoFrames:
            "The camera did not produce any video frames."
        }
    }
}

nonisolated public enum CameraRunCaptureState: Equatable, Sendable {
    case idle
    case requestingPermission
    case ready(mode: CameraRunCaptureMode, position: CameraRunCameraPosition)
    case running(mode: CameraRunCaptureMode, position: CameraRunCameraPosition)
    case interrupted(reason: String)
    case unavailable(CameraRunCaptureError)
    case failed(CameraRunCaptureError)
}

/// The output delegate is intentionally tiny.  It records the latest host
/// timestamp and forwards actual camera samples to an optional video writer;
/// it never fabricates sensor frames or timestamps.
private final class CameraRunTimestampBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<Double?>(initialState: nil)

    var latest: Double? {
        lock.withLock { $0 }
    }

    func record(_ timestampS: Double) {
        guard timestampS.isFinite else { return }
        lock.withLock { $0 = timestampS }
    }
}

private final class CameraRunVideoSinkBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<[CameraRunCameraPosition: CameraRunVideoRecorder]>(
        initialState: [:]
    )

    func set(_ recorder: CameraRunVideoRecorder?, for position: CameraRunCameraPosition) {
        lock.withLock { recorders in
            recorders[position] = recorder
        }
    }

    func clear() {
        lock.withLock { $0.removeAll() }
    }

    func append(_ sampleBuffer: CMSampleBuffer, from position: CameraRunCameraPosition) {
        let sample = CameraRunSampleBufferBox(sampleBuffer)
        lock.withLock { recorders in
            recorders[position]?.consume(sample.value)
        }
    }
}

nonisolated private final class CameraRunSampleBufferBox: @unchecked Sendable {
    let value: CMSampleBuffer

    init(_ value: CMSampleBuffer) {
        self.value = value
    }
}

private final class CameraRunSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let timestamps: CameraRunTimestampBox
    private let sink: CameraRunVideoSinkBox
    private let position: CameraRunCameraPosition

    init(
        timestamps: CameraRunTimestampBox,
        sink: CameraRunVideoSinkBox,
        position: CameraRunCameraPosition
    ) {
        self.timestamps = timestamps
        self.sink = sink
        self.position = position
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if presentationTime.isValid, presentationTime.seconds.isFinite {
            timestamps.record(presentationTime.seconds)
        }
        sink.append(sampleBuffer, from: position)
    }
}

/// Main-actor owner for AVFoundation's capture graph.  Camera permissions and
/// session mutations stay on the main actor; the sample-buffer delegate only
/// forwards immutable AVFoundation buffers to the optional recorder queue.
@MainActor
@Observable
public final class CameraRunCaptureSession {
    @ObservationIgnored public private(set) var session: AVCaptureSession = AVCaptureSession()

    public private(set) var state: CameraRunCaptureState = .idle
    public private(set) var permission = CameraRunPermissionSnapshot()
    public private(set) var capabilities: CameraRunCaptureCapabilities
    public private(set) var activeMode: CameraRunCaptureMode?
    public private(set) var activePosition: CameraRunCameraPosition?

    private let logger = Logger(subsystem: "tech.sateler.kamikazephone.dev", category: "camera-run")
    private let timestamps = CameraRunTimestampBox()
    private let videoSink = CameraRunVideoSinkBox()
    private var delegates: [CameraRunSampleBufferDelegate] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var requestedMode: CameraRunCaptureMode = .singleCamera
    private var requestedPosition: CameraRunCameraPosition = .rear

    public init() {
        capabilities = Self.detectCapabilities()
        registerNotifications()
    }

    public var latestVideoTimestampS: Double? { timestamps.latest }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// A preview layer is created on demand because the session can switch
    /// from a multi-cam graph to a single-cam graph during capability fallback.
    public func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        AVCaptureVideoPreviewLayer(session: session)
    }

    /// Configures the requested graph. Unsupported multi-cam devices, and
    /// devices where adding both inputs fails, deliberately fall back to one
    /// camera and report the selected mode to the caller.
    @discardableResult
    public func prepare(
        position: CameraRunCameraPosition = .rear,
        mode: CameraRunCaptureMode = .singleCamera
    ) async throws -> CameraRunCaptureMode {
        requestedMode = mode
        requestedPosition = position
        state = .requestingPermission

        #if targetEnvironment(simulator)
        state = .unavailable(.simulatorUnavailable)
        permission.camera = .unavailable
        throw CameraRunCaptureError.simulatorUnavailable
        #else
        guard capabilities.hasAnyCamera else {
            state = .unavailable(.cameraUnavailable)
            permission.camera = .unavailable
            throw CameraRunCaptureError.cameraUnavailable
        }

        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            permission.camera = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission.camera = granted ? .authorized : .denied
            guard granted else {
                state = .unavailable(.permissionDenied)
                throw CameraRunCaptureError.permissionDenied
            }
        case .denied:
            permission.camera = .denied
            state = .unavailable(.permissionDenied)
            throw CameraRunCaptureError.permissionDenied
        case .restricted:
            permission.camera = .restricted
            state = .unavailable(.permissionRestricted)
            throw CameraRunCaptureError.permissionRestricted
        @unknown default:
            permission.camera = .restricted
            state = .unavailable(.permissionRestricted)
            throw CameraRunCaptureError.permissionRestricted
        }

        capabilities = Self.detectCapabilities()
        guard capabilities.hasAnyCamera else {
            state = .unavailable(.cameraUnavailable)
            throw CameraRunCaptureError.cameraUnavailable
        }

        if mode == .multiCamera, capabilities.supportsMultiCamera,
           capabilities.hasFrontCamera, capabilities.hasRearCamera,
           configureMultiCamera() {
            activeMode = .multiCamera
            activePosition = nil
            state = .ready(mode: .multiCamera, position: position)
            return .multiCamera
        }

        let singlePosition = cameraDevice(for: position) != nil
            ? position
            : (position == .rear ? .front : .rear)
        guard cameraDevice(for: singlePosition) != nil else {
            state = .unavailable(.requiredPositionUnavailable(position))
            throw CameraRunCaptureError.requiredPositionUnavailable(position)
        }
        do {
            try configureSingleCamera(position: singlePosition)
        } catch let error as CameraRunCaptureError {
            state = .failed(error)
            throw error
        } catch {
            let wrapped = CameraRunCaptureError.configurationFailed(error.localizedDescription)
            state = .failed(wrapped)
            throw wrapped
        }
        activeMode = .singleCamera
        activePosition = singlePosition
        state = .ready(mode: .singleCamera, position: singlePosition)
        return .singleCamera
        #endif
    }

    public func attachVideoRecorder(
        _ recorder: CameraRunVideoRecorder?,
        for position: CameraRunCameraPosition
    ) {
        videoSink.set(recorder, for: position)
    }

    public func detachVideoRecorders() {
        videoSink.clear()
    }

    public func start() throws {
        guard case let .ready(mode, position) = state else {
            if case let .unavailable(error) = state { throw error }
            if case let .failed(error) = state { throw error }
            throw CameraRunCaptureError.configurationFailed("The camera session is not ready.")
        }
        guard !session.isRunning else { return }
        session.startRunning()
        guard session.isRunning else {
            let error = CameraRunCaptureError.runtime("AVCaptureSession did not start.")
            state = .failed(error)
            throw error
        }
        state = .running(mode: mode, position: position)
    }

    public func stop() {
        guard session.isRunning else {
            if let activeMode, let activePosition {
                state = .ready(mode: activeMode, position: activePosition)
            }
            return
        }
        session.stopRunning()
        if let activeMode {
            state = .ready(mode: activeMode, position: activePosition ?? .rear)
        } else {
            state = .idle
        }
    }

    public func switchCamera() async throws {
        guard activeMode == .singleCamera else {
            throw CameraRunCaptureError.configurationFailed("Switching a multi-camera graph requires stopping the run first.")
        }
        let next: CameraRunCameraPosition = activePosition == .front ? .rear : .front
        stop()
        try await prepare(position: next, mode: .singleCamera)
    }

    private func configureSingleCamera(position: CameraRunCameraPosition) throws {
        let device = try requiredCameraDevice(for: position)
        let newSession = AVCaptureSession()
        newSession.beginConfiguration()
        newSession.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        guard newSession.canAddInput(input) else {
            newSession.commitConfiguration()
            throw CameraRunCaptureError.configurationFailed("The \(position.rawValue) input cannot be added.")
        }
        newSession.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        let delegate = CameraRunSampleBufferDelegate(
            timestamps: timestamps,
            sink: videoSink,
            position: position
        )
        let queue = DispatchQueue(label: "kamikaze.camera-run.video.single", qos: .userInitiated)
        output.setSampleBufferDelegate(delegate, queue: queue)
        guard newSession.canAddOutput(output) else {
            newSession.commitConfiguration()
            throw CameraRunCaptureError.configurationFailed("The video output cannot be added.")
        }
        newSession.addOutput(output)
        setPortrait(on: output.connection(with: .video))
        newSession.commitConfiguration()
        session = newSession
        delegates = [delegate]
    }

    private func configureMultiCamera() -> Bool {
        guard let frontDevice = cameraDevice(for: .front),
              let rearDevice = cameraDevice(for: .rear) else { return false }
        let newSession = AVCaptureMultiCamSession()
        newSession.beginConfiguration()
        newSession.sessionPreset = .high
        do {
            let frontInput = try AVCaptureDeviceInput(device: frontDevice)
            let rearInput = try AVCaptureDeviceInput(device: rearDevice)
            guard newSession.canAddInput(frontInput), newSession.canAddInput(rearInput) else {
                newSession.commitConfiguration()
                return false
            }
            newSession.addInput(frontInput)
            newSession.addInput(rearInput)

            let frontOutput = AVCaptureVideoDataOutput()
            let rearOutput = AVCaptureVideoDataOutput()
            frontOutput.alwaysDiscardsLateVideoFrames = true
            rearOutput.alwaysDiscardsLateVideoFrames = true
            let frontDelegate = CameraRunSampleBufferDelegate(
                timestamps: timestamps,
                sink: videoSink,
                position: .front
            )
            let rearDelegate = CameraRunSampleBufferDelegate(
                timestamps: timestamps,
                sink: videoSink,
                position: .rear
            )
            frontOutput.setSampleBufferDelegate(
                frontDelegate,
                queue: DispatchQueue(label: "kamikaze.camera-run.video.front", qos: .userInitiated)
            )
            rearOutput.setSampleBufferDelegate(
                rearDelegate,
                queue: DispatchQueue(label: "kamikaze.camera-run.video.rear", qos: .userInitiated)
            )
            guard newSession.canAddOutput(frontOutput), newSession.canAddOutput(rearOutput) else {
                newSession.commitConfiguration()
                return false
            }
            newSession.addOutput(frontOutput)
            newSession.addOutput(rearOutput)
            setPortrait(on: frontOutput.connection(with: .video))
            setPortrait(on: rearOutput.connection(with: .video))
            newSession.commitConfiguration()
            session = newSession
            delegates = [frontDelegate, rearDelegate]
            return true
        } catch {
            newSession.commitConfiguration()
            logger.debug("Multi-camera configuration fell back: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func requiredCameraDevice(for position: CameraRunCameraPosition) throws -> AVCaptureDevice {
        guard let device = cameraDevice(for: position) else {
            throw CameraRunCaptureError.requiredPositionUnavailable(position)
        }
        return device
    }

    private func cameraDevice(for position: CameraRunCameraPosition) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInTrueDepthCamera,
                .builtInUltraWideCamera
            ],
            mediaType: .video,
            position: position.avPosition
        )
        return discovery.devices.first
    }

    private static func detectCapabilities() -> CameraRunCaptureCapabilities {
        #if targetEnvironment(simulator)
        return CameraRunCaptureCapabilities(
            hasFrontCamera: false,
            hasRearCamera: false,
            supportsMultiCamera: false
        )
        #else
        let front = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .front
        ).devices.isEmpty == false
        let rear = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .back
        ).devices.isEmpty == false
        return CameraRunCaptureCapabilities(
            hasFrontCamera: front,
            hasRearCamera: rear,
            supportsMultiCamera: AVCaptureMultiCamSession.isMultiCamSupported
        )
        #endif
    }

    private func setPortrait(on connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    private func registerNotifications() {
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int)
                .map(String.init) ?? "unknown"
            Task { @MainActor [weak self] in
                self?.state = .interrupted(reason: reason)
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                if let self, let activeMode = self.activeMode {
                    self.state = .ready(mode: activeMode, position: self.activePosition ?? .rear)
                }
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                ?? "Unknown AVCaptureSession error."
            Task { @MainActor [weak self] in
                self?.state = .failed(.runtime(reason))
            }
        })
    }
}
