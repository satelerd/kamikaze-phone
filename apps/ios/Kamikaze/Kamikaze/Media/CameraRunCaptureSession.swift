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
nonisolated private final class CameraRunTimestampBox: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<Double?>(initialState: nil)

    var latest: Double? {
        lock.withLock { $0 }
    }

    func record(_ timestampS: Double) {
        guard timestampS.isFinite else { return }
        lock.withLock { $0 = timestampS }
    }
}

nonisolated private final class CameraRunVideoSinkBox: @unchecked Sendable {
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

nonisolated private final class CameraRunSampleBufferDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let timestamps: CameraRunTimestampBox
    private let sink: CameraRunVideoSinkBox
    private let position: CameraRunCameraPosition
    private let videoRenderer: AVSampleBufferVideoRenderer?

    init(
        timestamps: CameraRunTimestampBox,
        sink: CameraRunVideoSinkBox,
        position: CameraRunCameraPosition,
        videoRenderer: AVSampleBufferVideoRenderer? = nil
    ) {
        self.timestamps = timestamps
        self.sink = sink
        self.position = position
        self.videoRenderer = videoRenderer
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
        if let videoRenderer, videoRenderer.isReadyForMoreMediaData {
            videoRenderer.enqueue(sampleBuffer)
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
    @ObservationIgnored public private(set) var previewLayer = AVCaptureVideoPreviewLayer()
    /// iOS 26 RealityKit can consume this renderer directly as a VideoMaterial,
    /// letting the real selfie feed live on the moving 3D phone screen.
    @ObservationIgnored public let frontVideoRenderer = AVSampleBufferVideoRenderer()

    public private(set) var state: CameraRunCaptureState = .idle
    public private(set) var permission = CameraRunPermissionSnapshot()
    public private(set) var capabilities: CameraRunCaptureCapabilities
    public private(set) var activeMode: CameraRunCaptureMode?
    public private(set) var activePosition: CameraRunCameraPosition?

    private let logger = Logger(subsystem: "tech.sateler.kamikazephone.dev", category: "camera-run")
    /// AVFoundation documents `startRunning` and `stopRunning` as blocking
    /// operations. Keeping them on a dedicated serial queue prevents Camera
    /// Run from trapping or freezing SwiftUI's main actor on entry.
    @ObservationIgnored private let sessionQueue = DispatchQueue(
        label: "kamikaze.camera-run.session",
        qos: .userInitiated
    )
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

    /// Configures the requested graph. Unsupported multi-cam devices, and
    /// devices where adding both inputs fails, deliberately fall back to one
    /// camera and report the selected mode to the caller.
    @discardableResult
    public func prepare(
        position: CameraRunCameraPosition = .rear,
        mode: CameraRunCaptureMode = .singleCamera
    ) async throws -> CameraRunCaptureMode {
        logger.info("Preparing camera graph: mode=\(mode.rawValue, privacy: .public) position=\(position.rawValue, privacy: .public)")
        requestedMode = mode
        requestedPosition = position
        state = .requestingPermission
        frontVideoRenderer.flush()

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
            logger.info("Camera graph ready: multi-camera")
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
        logger.info("Camera graph ready: single \(singlePosition.rawValue, privacy: .public)")
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

    public func start() async throws {
        guard case let .ready(mode, position) = state else {
            if case let .unavailable(error) = state { throw error }
            if case let .failed(error) = state { throw error }
            throw CameraRunCaptureError.configurationFailed("The camera session is not ready.")
        }
        guard !session.isRunning else { return }
        let session = self.session
        logger.info("Starting camera session off main actor")
        let didStart = await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume(returning: session.isRunning)
            }
        }
        guard didStart else {
            let error = CameraRunCaptureError.runtime("AVCaptureSession did not start.")
            state = .failed(error)
            throw error
        }
        state = .running(mode: mode, position: position)
        logger.info("Camera session running")
    }

    public func stop() async {
        let session = self.session
        guard session.isRunning else {
            if let activeMode, let activePosition {
                state = .ready(mode: activeMode, position: activePosition)
            }
            return
        }
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.stopRunning()
                continuation.resume()
            }
        }
        logger.info("Camera session stopped")
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
        await stop()
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
            position: position,
            videoRenderer: position == .front ? frontVideoRenderer : nil
        )
        let queue = DispatchQueue(label: "kamikaze.camera-run.video.single", qos: .userInitiated)
        output.setSampleBufferDelegate(delegate, queue: queue)
        guard newSession.canAddOutput(output) else {
            newSession.commitConfiguration()
            throw CameraRunCaptureError.configurationFailed("The video output cannot be added.")
        }
        newSession.addOutput(output)
        let videoConnection = output.connection(with: .video)
        setPortrait(on: videoConnection)
        if position == .front { setMirrored(on: videoConnection) }
        newSession.commitConfiguration()
        previewLayer = AVCaptureVideoPreviewLayer(session: newSession)
        previewLayer.videoGravity = .resizeAspectFill
        session = newSession
        delegates = [delegate]
    }

    private func configureMultiCamera() -> Bool {
        guard let frontDevice = cameraDevice(for: .front),
              let rearDevice = cameraDevice(for: .rear) else { return false }
        let newSession = AVCaptureMultiCamSession()
        newSession.beginConfiguration()
        do {
            let frontInput = try AVCaptureDeviceInput(device: frontDevice)
            let rearInput = try AVCaptureDeviceInput(device: rearDevice)
            guard newSession.canAddInput(frontInput), newSession.canAddInput(rearInput) else {
                newSession.commitConfiguration()
                return false
            }
            newSession.addInputWithNoConnections(frontInput)
            newSession.addInputWithNoConnections(rearInput)

            let frontOutput = AVCaptureVideoDataOutput()
            let rearOutput = AVCaptureVideoDataOutput()
            frontOutput.alwaysDiscardsLateVideoFrames = true
            rearOutput.alwaysDiscardsLateVideoFrames = true
            let frontDelegate = CameraRunSampleBufferDelegate(
                timestamps: timestamps,
                sink: videoSink,
                position: .front,
                videoRenderer: frontVideoRenderer
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
            newSession.addOutputWithNoConnections(frontOutput)
            newSession.addOutputWithNoConnections(rearOutput)

            guard let frontPort = frontInput.ports.first(where: { $0.mediaType == .video }),
                  let rearPort = rearInput.ports.first(where: { $0.mediaType == .video }) else {
                newSession.commitConfiguration()
                return false
            }

            let frontOutputConnection = AVCaptureConnection(inputPorts: [frontPort], output: frontOutput)
            let rearOutputConnection = AVCaptureConnection(inputPorts: [rearPort], output: rearOutput)
            guard newSession.canAddConnection(frontOutputConnection),
                  newSession.canAddConnection(rearOutputConnection) else {
                newSession.commitConfiguration()
                return false
            }
            newSession.addConnection(frontOutputConnection)
            newSession.addConnection(rearOutputConnection)
            setPortrait(on: frontOutputConnection)
            setPortrait(on: rearOutputConnection)
            setMirrored(on: frontOutputConnection)

            let primaryPort = requestedPosition == .front ? frontPort : rearPort
            let newPreviewLayer = AVCaptureVideoPreviewLayer()
            newPreviewLayer.videoGravity = .resizeAspectFill
            newPreviewLayer.setSessionWithNoConnection(newSession)
            let previewConnection = AVCaptureConnection(inputPort: primaryPort, videoPreviewLayer: newPreviewLayer)
            guard newSession.canAddConnection(previewConnection) else {
                newSession.commitConfiguration()
                return false
            }
            newSession.addConnection(previewConnection)
            setPortrait(on: previewConnection)
            newSession.commitConfiguration()
            previewLayer = newPreviewLayer
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

    private func setMirrored(on connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
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
