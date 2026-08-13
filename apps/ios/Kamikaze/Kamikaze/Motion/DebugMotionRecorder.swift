import CryptoKit
import Foundation
import KamikazeMotionApple
import KamikazeMotionCore
import Observation
import UIKit

/// A deliberately separate recorder for collecting labelled raw evidence while
/// the detector is being tuned. It owns Core Motion only while Workshop is on
/// screen, so it never participates in the player-facing Play loop.
@MainActor
@Observable
final class DebugMotionRecorder {
    enum State: Equatable {
        case idle
        case monitoring
        case recording
        case postRoll
        case saving
        case saved
        case unavailable
        case failed(String)
    }

    private struct PendingCapture {
        let id: String
        let label: DebugMotionCaptureLabel
        let motionStartS: Double
        var motionEndS: Double?
        var postRollEndsS: Double?
        var samples: [MotionSampleV3]
        var automaticObservation: DebugAutomaticObservation?
    }

    private let source = CoreMotionSource()
    private let requestedFrequencyHz = 100.0
    private let preRollSeconds = 0.35
    private let postRollSeconds = 0.35
    private var streamTask: Task<Void, Never>?
    private var preRoll: [MotionSampleV3] = []
    private var pending: PendingCapture?
    private var sequence: UInt64 = 0
    private var previousTimestampS: Double?
    private var latestTimestampS: Double?
    private var detector = MotionDetector()

    private(set) var state: State = .idle
    private(set) var measuredHz = 0.0
    /// Gaps are inferred from monotonic Core Motion timestamps. The source uses
    /// a bounded async buffer, so this counter is intentionally visible rather
    /// than claiming every requested 100 Hz frame arrived.
    private(set) var timestampGapCount = 0
    private(set) var lastSaved: DebugSavedMotionCapture?
    private(set) var automaticObservation: DebugAutomaticObservation?

    var isRecording: Bool {
        if case .recording = state { return true }
        if case .postRoll = state { return true }
        return false
    }

    var isSaving: Bool {
        if case .saving = state { return true }
        return false
    }

    var statusText: String {
        switch state {
        case .idle: "IDLE"
        case .monitoring: "SENSOR READY"
        case .recording: "RECORDING"
        case .postRoll: "CAPTURING POST-ROLL"
        case .saving: "SAVING"
        case .saved: "SAVED"
        case .unavailable: "MOTION UNAVAILABLE"
        case .failed: "RECORDER ERROR"
        }
    }

    func start() {
        guard streamTask == nil else { return }
        guard source.isAvailable else {
            state = .unavailable
            return
        }

        state = .monitoring
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await frame in source.frames(frequencyHz: requestedFrequencyHz) {
                    guard !Task.isCancelled else { break }
                    ingest(frame)
                }
            } catch is CancellationError {
                // Expected when Workshop leaves the screen.
            } catch {
                state = .failed(error.localizedDescription)
            }
            streamTask = nil
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        source.stop()
        pending = nil
        preRoll = []
        previousTimestampS = nil
        latestTimestampS = nil
        measuredHz = 0
        timestampGapCount = 0
        if state != .unavailable { state = .idle }
    }

    func beginCapture(label: DebugMotionCaptureLabel) {
        guard !isRecording, !isSaving else { return }
        guard state != .unavailable else { return }
        guard let marker = latestTimestampS ?? preRoll.last?.timestampS else {
            state = .failed("Wait for the motion sensor to become ready.")
            return
        }

        let id = UUID().uuidString.lowercased()
        detector = MotionDetector()
        _ = detector.arm()
        // Feed the same pre-roll into the debug detector that is preserved in
        // the export. This is only a diagnostic hint, never the human label.
        for sample in preRoll {
            _ = detector.process(legacySample(from: sample))
        }
        let capturedPreRoll = preRoll
        pending = PendingCapture(
            id: id,
            label: label.normalized,
            motionStartS: marker,
            motionEndS: nil,
            postRollEndsS: nil,
            samples: capturedPreRoll,
            automaticObservation: nil
        )
        automaticObservation = nil
        state = .recording
    }

    func endCapture() {
        guard var pending, pending.motionEndS == nil else { return }
        let end = latestTimestampS ?? pending.motionStartS
        pending.motionEndS = end
        pending.postRollEndsS = end + postRollSeconds
        self.pending = pending
        state = .postRoll
    }

    private func ingest(_ frame: AppleMotionFrame) {
        let sample = makeSample(from: frame)
        latestTimestampS = sample.timestampS

        guard var pending else {
            appendToPreRoll(sample)
            return
        }
        pending.samples.append(sample)
        let snapshot = detector.process(legacySample(from: sample))
        if let attempt = snapshot.lastAttempt {
            let observation = DebugAutomaticObservation(
                trick: attempt.trick,
                confidence: attempt.confidence,
                triggerMode: attempt.triggerMode?.rawValue,
                detectorVersion: "debug-recorder/v1"
            )
            pending.automaticObservation = observation
            automaticObservation = observation
        }
        self.pending = pending

        if let postRollEndsS = pending.postRollEndsS, sample.timestampS >= postRollEndsS {
            finalize(pending)
        }
        appendToPreRoll(sample)
    }

    private func makeSample(from frame: AppleMotionFrame) -> MotionSampleV3 {
        var flags: MotionSampleQualityFlags = []
        if let previousTimestampS {
            let interval = frame.timestampS - previousTimestampS
            if interval == 0 { flags.insert(.timestampDuplicate) }
            if interval < 0 { flags.insert(.timestampNonMonotonic) }
            if interval > (1 / requestedFrequencyHz) * 2.5 {
                flags.insert(.timestampGapBefore)
                timestampGapCount += 1
            }
            if interval > 0 {
                let instantaneous = 1 / interval
                measuredHz = measuredHz == 0
                    ? instantaneous
                    : measuredHz * 0.88 + instantaneous * 0.12
            }
        }
        previousTimestampS = frame.timestampS
        defer { sequence += 1 }

        return MotionSampleV3(
            sequence: sequence,
            timestampS: frame.timestampS,
            rotationRateRadS: frame.rotationRateRadiansPerSecond,
            userAccelerationG: frame.userAccelerationG,
            gravityG: frame.gravityG,
            fusedAttitude: frame.attitude,
            qualityFlags: flags
        )
    }

    private func appendToPreRoll(_ sample: MotionSampleV3) {
        preRoll.append(sample)
        let cutoff = sample.timestampS - preRollSeconds
        while preRoll.first?.timestampS ?? .infinity < cutoff {
            preRoll.removeFirst()
        }
    }

    private func finalize(_ pending: PendingCapture) {
        guard let first = pending.samples.first,
              let last = pending.samples.last,
              let motionEndS = pending.motionEndS else {
            self.pending = nil
            state = .failed("Capture contained no usable samples.")
            return
        }

        self.pending = nil
        state = .saving
        let capture: MotionCaptureV3
        do {
            capture = try makeCapture(
                id: pending.id,
                label: pending.label,
                samples: pending.samples,
                captureStartS: first.timestampS,
                captureEndS: last.timestampS,
                motionStartS: pending.motionStartS,
                motionEndS: motionEndS
            )
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        let label = pending.label
        let automaticObservation = pending.automaticObservation

        Task.detached(priority: .utility) {
            do {
                let saved = try DebugMotionCaptureStore.save(
                    capture: capture,
                    label: label,
                    automaticObservation: automaticObservation
                )
                await MainActor.run {
                    self.lastSaved = saved
                    self.state = .saved
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func makeCapture(
        id: String,
        label: DebugMotionCaptureLabel,
        samples: [MotionSampleV3],
        captureStartS: Double,
        captureEndS: Double,
        motionStartS: Double,
        motionEndS: Double
    ) throws -> MotionCaptureV3 {
        let samplePayload = MotionSamplePayloadV3(attemptID: id, samples: samples)
        let payloadData = try DebugMotionCaptureStore.encodedJSON(samplePayload)
        let checksum = DebugMotionCaptureStore.sha256(payloadData)
        let rawName = "\(id).samples.v3.json"
        let boundaries = AttemptBoundariesV3(
            captureStartS: captureStartS,
            captureEndS: captureEndS,
            motionStartS: motionStartS,
            motionEndS: motionEndS,
            releaseS: nil,
            catchS: nil,
            settledS: nil
        )
        let environment = CaptureEnvironmentV3(
            device: Self.deviceMetadata(),
            gripHand: label.gripHand,
            orientation: Self.captureOrientation(),
            referenceFrame: .xArbitraryZVertical,
            requestedFrequencyHz: requestedFrequencyHz,
            measuredFrequencyHz: Self.measuredFrequency(for: samples)
        )
        let versions = ProcessingVersionsV3(
            calibrationProfileID: nil,
            calibrationVersion: nil,
            detectorVersion: "debug-recorder/v1",
            analysisVersion: "unanalysed/debug-recorder/v1",
            scoreVersion: nil
        )
        let rawReference = RawSampleReferenceV3(
            relativePath: rawName,
            encoding: .json,
            payloadSchemaVersion: MotionSchemaV3.version,
            sampleCount: samples.count,
            checksum: checksum
        )
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            captureMode: .manual,
            triggerMode: nil,
            boundaries: boundaries,
            environment: environment,
            versions: versions,
            rawSamples: rawReference,
            importedExpoAnalysis: nil
        )
        return MotionCaptureV3(attempt: attempt, samplePayload: samplePayload)
    }

    private static func measuredFrequency(for samples: [MotionSampleV3]) -> Double? {
        guard samples.count > 1 else { return nil }
        let intervals = zip(samples, samples.dropFirst()).compactMap { previous, current -> Double? in
            let interval = current.timestampS - previous.timestampS
            return interval > 0 ? interval : nil
        }
        let elapsed = intervals.reduce(0, +)
        guard elapsed > 0 else { return nil }
        return Double(intervals.count) / elapsed
    }

    private static func deviceMetadata() -> CaptureDeviceMetadataV3 {
        let device = UIDevice.current
        return CaptureDeviceMetadataV3(
            modelIdentifier: machineIdentifier(),
            modelName: device.model,
            operatingSystemName: device.systemName,
            operatingSystemVersion: device.systemVersion,
            operatingSystemBuild: nil
        )
    }

    private static func captureOrientation() -> CaptureOrientation {
        switch UIDevice.current.orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        // The app is portrait-locked; a phone resting flat often reports an
        // unknown device orientation, which should not erase that context.
        default: .portrait
        }
    }

    private static func machineIdentifier() -> String? {
        var info = utsname()
        guard uname(&info) == 0 else { return nil }
        var machine = info.machine
        let capacity = MemoryLayout.size(ofValue: machine)
        return withUnsafePointer(to: &machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }

    private func legacySample(from sample: MotionSampleV3) -> MotionSample {
        let acceleration = sample.accelerationIncludingGravityG ?? Vector3(x: 0, y: 0, z: 0)
        return MotionSample(
            timestampS: sample.timestampS,
            accelerationIncludingGravity: Vector3(
                x: acceleration.x * MotionSchemaV3.earthGravityMetersPerSecondSquared,
                y: acceleration.y * MotionSchemaV3.earthGravityMetersPerSecondSquared,
                z: acceleration.z * MotionSchemaV3.earthGravityMetersPerSecondSquared
            ),
            rotationRateDps: Vector3(
                x: sample.rotationRateRadS.x * 180 / .pi,
                y: sample.rotationRateRadS.y * 180 / .pi,
                z: sample.rotationRateRadS.z * 180 / .pi
            )
        )
    }
}

nonisolated struct DebugMotionCaptureLabel: Codable, Equatable, Sendable {
    var expectedTrick: String
    var gripHand: GripHand
    var caseState: DebugPhoneCaseState
    var condition: DebugMotionCaptureCondition
    var outcome: DebugMotionCaptureOutcome
    var rhythmNotes: String

    var normalized: Self {
        Self(
            expectedTrick: expectedTrick.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().isEmpty
                ? "UNLABELLED"
                : expectedTrick.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            gripHand: gripHand,
            caseState: caseState,
            condition: condition,
            outcome: outcome,
            rhythmNotes: rhythmNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

nonisolated enum DebugPhoneCaseState: String, Codable, CaseIterable, Sendable {
    case withCase
    case withoutCase
    case unknown

    var title: String {
        switch self {
        case .withCase: "WITH CASE"
        case .withoutCase: "WITHOUT CASE"
        case .unknown: "CASE UNKNOWN"
        }
    }
}

nonisolated enum DebugMotionCaptureCondition: String, Codable, CaseIterable, Sendable {
    case standard
    case fastLow
    case highFreefall
    case negativeControl

    var title: String {
        switch self {
        case .standard: "STANDARD"
        case .fastLow: "FAST / LOW"
        case .highFreefall: "HIGH / FREEFALL"
        case .negativeControl: "FAILED / NEGATIVE"
        }
    }
}

nonisolated enum DebugMotionCaptureOutcome: String, Codable, CaseIterable, Sendable {
    case landed
    case missed
    case unclear
    case calibration

    var title: String {
        switch self {
        case .landed: "LANDED"
        case .missed: "MISSED"
        case .unclear: "UNCLEAR"
        case .calibration: "CALIBRATION"
        }
    }
}

/// A detector suggestion exported beside, never inside, the player-provided
/// label. Future dataset tooling must treat it as a model observation only.
nonisolated struct DebugAutomaticObservation: Codable, Equatable, Sendable {
    let trick: String
    let confidence: Double
    let triggerMode: String?
    let detectorVersion: String
}

nonisolated struct DebugMotionCaptureExportV1: Codable, Sendable {
    let format: String
    let exportedAtISO8601: String
    let label: DebugMotionCaptureLabel
    let automaticObservation: DebugAutomaticObservation?
    let capture: MotionCaptureV3

    init(
        label: DebugMotionCaptureLabel,
        automaticObservation: DebugAutomaticObservation?,
        capture: MotionCaptureV3
    ) {
        format = "kamikaze.debug-motion-capture.v1"
        exportedAtISO8601 = ISO8601DateFormatter().string(from: Date())
        self.label = label
        self.automaticObservation = automaticObservation
        self.capture = capture
    }
}

nonisolated struct DebugSavedMotionCapture: Equatable, Sendable {
    let exportURL: URL
    let sampleURL: URL
    let sampleCount: Int
}

nonisolated enum DebugMotionCaptureStore {
    nonisolated enum StoreError: LocalizedError, Sendable {
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .checksumMismatch: "The raw sample checksum did not match the capture metadata."
            }
        }
    }

    nonisolated static func save(
        capture: MotionCaptureV3,
        label: DebugMotionCaptureLabel,
        automaticObservation: DebugAutomaticObservation?
    ) throws -> DebugSavedMotionCapture {
        let directory = try captureDirectory()
        let sampleData = try encodedJSON(capture.samplePayload)
        guard sha256(sampleData) == capture.attempt.rawSamples.checksum else {
            throw StoreError.checksumMismatch
        }

        let sampleURL = directory.appending(path: capture.attempt.rawSamples.relativePath)
        try sampleData.write(to: sampleURL, options: .atomic)

        let export = DebugMotionCaptureExportV1(
            label: label,
            automaticObservation: automaticObservation,
            capture: capture
        )
        let exportData = try encodedJSON(export)
        let exportURL = directory.appending(path: "\(capture.attempt.id).kamikaze-motion-v3.json")
        try exportData.write(to: exportURL, options: .atomic)

        return DebugSavedMotionCapture(
            exportURL: exportURL,
            sampleURL: sampleURL,
            sampleCount: capture.samplePayload.samples.count
        )
    }

    nonisolated static func encodedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    nonisolated static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func captureDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appending(path: "Kamikaze/DebugMotionCaptures")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
