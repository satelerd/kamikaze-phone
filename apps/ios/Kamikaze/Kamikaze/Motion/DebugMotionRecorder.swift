import CryptoKit
import Darwin
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
        case reviewing
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

    private let source = CoreMotionSampleSource()
    private let requestedFrequencyHz = 100.0
    private let preRollSeconds = 0.35
    private let postRollSeconds = 0.35
    private var streamTask: Task<Void, Never>?
    private var preRoll: [MotionSampleV3] = []
    private var pending: PendingCapture?
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
    private(set) var reviewDraft: DebugMotionCaptureDraft?
    private(set) var labelledDatasetExport: DebugSavedDatasetExport?

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
        case .reviewing: "REVIEW LABEL"
        case .saving: "VERIFYING + SAVING"
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
        refreshLabelledDatasetExport()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await sample in source.samples(configuration: MotionStreamConfiguration(
                    requestedFrequencyHz: requestedFrequencyHz,
                    ringBufferDurationS: preRollSeconds,
                    timestampGapFactor: 1.5
                )) {
                    guard !Task.isCancelled else { break }
                    ingest(sample)
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
        reviewDraft = nil
        preRoll = []
        previousTimestampS = nil
        latestTimestampS = nil
        measuredHz = 0
        timestampGapCount = 0
        if state != .unavailable { state = .idle }
    }

    /// The review owns a RealityKit replay. Stop the 100 Hz producer while it
    /// is visible so the hidden lab cannot keep invalidating SwiftUI behind
    /// the full-screen cover. The draft and its raw evidence remain intact.
    func pauseMonitoringForReview() {
        guard reviewDraft != nil else { return }
        streamTask?.cancel()
        streamTask = nil
        source.stop()
        preRoll = []
        previousTimestampS = nil
        latestTimestampS = nil
        measuredHz = 0
        state = .reviewing
    }

    func resumeMonitoringAfterReview() {
        guard reviewDraft == nil, streamTask == nil else { return }
        start()
    }

    func beginCapture(label: DebugMotionCaptureLabel) {
        guard !isRecording, !isSaving else { return }
        guard state != .unavailable else { return }
        guard let marker = latestTimestampS ?? preRoll.last?.timestampS else {
            state = .failed("Wait for the motion sensor to become ready.")
            return
        }

        let id = UUID().uuidString.lowercased()
        reviewDraft = nil
        lastSaved = nil
        detector = MotionDetector()
        _ = detector.arm()
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

    func interruptCapture() {
        guard pending != nil else { return }
        pending = nil
        _ = detector.disarm()
        automaticObservation = nil
        state = .failed("Capture interrupted by app lifecycle. Record it again.")
    }

    func saveReviewedCapture(label: DebugMotionCaptureLabel) {
        guard let draft = reviewDraft, !isSaving else { return }
        state = .saving
        let normalized = label.normalized
        Task.detached(priority: .utility) {
            do {
                let saved = try DebugMotionCaptureStore.save(
                    capture: draft.capture,
                    label: normalized,
                    automaticObservation: draft.automaticObservation
                )
                await MainActor.run {
                    self.lastSaved = saved
                    self.reviewDraft = nil
                    self.state = .saved
                    self.refreshLabelledDatasetExport()
                }
            } catch {
                await MainActor.run {
                    self.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func discardReview() {
        guard reviewDraft != nil else { return }
        reviewDraft = nil
        automaticObservation = nil
        state = .monitoring
    }

    func refreshLabelledDatasetExport() {
        Task.detached(priority: .utility) {
            let export = try? DebugMotionCaptureStore.exportClassifiedDataset()
            await MainActor.run {
                self.labelledDatasetExport = export
            }
        }
    }

    private func ingest(_ sample: MotionSampleV3) {
        latestTimestampS = sample.timestampS
        updateTiming(with: sample)

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

    private func updateTiming(with sample: MotionSampleV3) {
        if let previousTimestampS {
            let interval = sample.timestampS - previousTimestampS
            if interval > 0 {
                let instantaneous = 1 / interval
                measuredHz = measuredHz == 0
                    ? instantaneous
                    : measuredHz * 0.88 + instantaneous * 0.12
            }
        }
        previousTimestampS = sample.timestampS
        if sample.qualityFlags.contains(.timestampGapBefore)
            || sample.qualityFlags.contains(.sequenceGapBefore) {
            timestampGapCount += 1
        }
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
        let capture: MotionCaptureV3
        do {
            let refined = MotionBurstRefiner.primaryBurst(
                samples: pending.samples,
                markerStartS: pending.motionStartS,
                markerEndS: motionEndS
            )
            capture = try makeCapture(
                id: pending.id,
                label: pending.label,
                samples: pending.samples,
                captureStartS: first.timestampS,
                captureEndS: last.timestampS,
                motionStartS: refined?.startS ?? pending.motionStartS,
                motionEndS: refined?.endS ?? motionEndS
            )
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        reviewDraft = DebugMotionCaptureDraft(
            capture: capture,
            proposedLabel: pending.label,
            automaticObservation: pending.automaticObservation
        )
        state = .reviewing
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
            detectorVersion: "debug-recorder/manual-primary-burst-v2",
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
            operatingSystemBuild: operatingSystemBuild()
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

    private static func operatingSystemBuild() -> String? {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &value, &size, nil, 0) == 0 else { return nil }
        let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
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
    var expectedTrickID: DebugTrickID
    var gripHand: GripHand
    var caseState: DebugPhoneCaseState
    var condition: DebugMotionCaptureCondition
    var outcome: DebugMotionCaptureOutcome
    var rhythmNotes: String

    var normalized: Self {
        Self(
            expectedTrickID: expectedTrickID,
            gripHand: gripHand,
            caseState: caseState,
            condition: condition,
            outcome: outcome,
            rhythmNotes: rhythmNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

nonisolated struct DebugMotionCaptureDraft: Identifiable, Equatable, Sendable {
    var id: String { capture.attempt.id }
    let capture: MotionCaptureV3
    let proposedLabel: DebugMotionCaptureLabel
    let automaticObservation: DebugAutomaticObservation?
}

nonisolated enum DebugTrickID: String, Codable, CaseIterable, Hashable, Sendable {
    case phoneFlip = "phone-flip"
    case reversePhoneFlip = "reverse-phone-flip"
    case doublePhoneFlip = "double-phone-flip"
    case doubleReversePhoneFlip = "double-reverse-phone-flip"
    case flip = "flip"
    case reverseFlip = "reverse-flip"
    case doubleFlip = "double-flip"
    case doubleReverseFlip = "double-reverse-flip"
    case frontsideShuvit = "frontside-shuvit-180"
    case backsideShuvit = "backside-shuvit-180"
    case frontsideThreeSixtyShuvit = "frontside-360-shuvit"
    case backsideThreeSixtyShuvit = "backside-360-shuvit"
    case straightAir = "straight-air"
    case unknown

    var title: String {
        switch self {
        case .phoneFlip: "PHONE FLIP"
        case .reversePhoneFlip: "REVERSE PHONE FLIP"
        case .doublePhoneFlip: "DOUBLE PHONE FLIP"
        case .doubleReversePhoneFlip: "DOUBLE REVERSE PHONE FLIP"
        case .flip: "FLIP"
        case .reverseFlip: "REVERSE FLIP"
        case .doubleFlip: "DOUBLE FLIP"
        case .doubleReverseFlip: "DOUBLE REVERSE FLIP"
        case .frontsideShuvit: "FS SHUVIT"
        case .backsideShuvit: "BS SHUVIT"
        case .frontsideThreeSixtyShuvit: "FS 360 SHUVIT"
        case .backsideThreeSixtyShuvit: "BS 360 SHUVIT"
        case .straightAir: "STRAIGHT AIR"
        case .unknown: "UNKNOWN / NO TRICK"
        }
    }

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "front-flip": self = .flip
        case "back-flip": self = .reverseFlip
        // Dataset v1 used the plain Shuvit IDs for measured full rotations.
        case "frontside-shuvit": self = .frontsideThreeSixtyShuvit
        case "backside-shuvit": self = .backsideThreeSixtyShuvit
        default:
            guard let decoded = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unknown trick identifier: \(value)"
                )
            }
            self = decoded
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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
    case noAttempt
    case calibration

    var title: String {
        switch self {
        case .landed: "LANDED"
        case .missed: "MISSED"
        case .unclear: "UNCLEAR"
        case .noAttempt: "NO ATTEMPT"
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

nonisolated struct DebugMotionCaptureExportV1: Codable, Equatable, Sendable {
    let format: String
    let exportedAtISO8601: String
    let boundarySemantics: String
    let diagnostics: DebugMotionCaptureDiagnostics
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
        boundarySemantics = capture.attempt.versions.detectorVersion.contains("primary-burst-v2")
            ? "manual-capture-auto-primary-burst-v2"
            : "manual-ui-markers-v1"
        diagnostics = DebugMotionCaptureDiagnostics(samples: capture.samplePayload.samples)
        self.label = label
        self.automaticObservation = automaticObservation
        self.capture = capture
    }
}

nonisolated struct DebugMotionDatasetExportV1: Codable, Equatable, Sendable {
    let format: String
    let exportedAtISO8601: String
    let classificationRule: String
    let captures: [DebugMotionCaptureExportV1]

    init(captures: [DebugMotionCaptureExportV1]) {
        format = "kamikaze.labelled-motion-dataset.v1"
        exportedAtISO8601 = ISO8601DateFormatter().string(from: Date())
        classificationRule = "human-confirmed-outcome:landed|missed|no-attempt"
        self.captures = captures
    }
}

nonisolated struct DebugMotionCaptureDiagnostics: Codable, Equatable, Sendable {
    let timestampGapCount: Int
    let sequenceGapCount: Int

    init(samples: [MotionSampleV3]) {
        timestampGapCount = samples.count { $0.qualityFlags.contains(.timestampGapBefore) }
        sequenceGapCount = zip(samples, samples.dropFirst()).count { previous, current in
            current.sequence != previous.sequence + 1
        }
    }
}

nonisolated struct DebugSavedMotionCapture: Equatable, Sendable {
    let exportURL: URL
    let sampleURL: URL
    let sampleCount: Int
}

nonisolated struct DebugSavedDatasetExport: Equatable, Sendable {
    let exportURL: URL
    let captureCount: Int
    let countsByTrick: [DebugTrickID: Int]
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
        // The exact bytes exposed by ShareLink must pass the same importer the
        // dataset tooling uses. A capture is never presented as saved if its
        // embedded evidence cannot verify and replay by itself.
        _ = try validateExport(exportData)
        let exportURL = directory.appending(path: "\(capture.attempt.id).kamikaze-motion-v3.json")
        try exportData.write(to: exportURL, options: .atomic)

        return DebugSavedMotionCapture(
            exportURL: exportURL,
            sampleURL: sampleURL,
            sampleCount: capture.samplePayload.samples.count
        )
    }

    nonisolated static func validateExport(_ data: Data) throws -> DebugMotionCaptureExportV1 {
        let export: DebugMotionCaptureExportV1
        do {
            export = try JSONDecoder().decode(DebugMotionCaptureExportV1.self, from: data)
        } catch {
            throw ValidationError.malformedExport
        }
        guard export.format == "kamikaze.debug-motion-capture.v1" else {
            throw ValidationError.unsupportedFormat
        }
        let attempt = export.capture.attempt
        let payload = export.capture.samplePayload
        guard attempt.schemaVersion == MotionSchemaV3.version,
              payload.schemaVersion == MotionSchemaV3.version else {
            throw ValidationError.schemaMismatch
        }
        guard attempt.id == payload.attemptID else { throw ValidationError.attemptIDMismatch }
        guard attempt.rawSamples.sampleCount == payload.samples.count else {
            throw ValidationError.sampleCountMismatch
        }
        let canonicalPayload = try encodedJSON(payload)
        guard sha256(canonicalPayload) == attempt.rawSamples.checksum else {
            throw ValidationError.checksumMismatch
        }
        guard !payload.samples.isEmpty else { throw ValidationError.emptySamples }
        guard zip(payload.samples, payload.samples.dropFirst()).allSatisfy({ previous, current in
            current.timestampS > previous.timestampS && current.sequence == previous.sequence + 1
        }) else {
            throw ValidationError.nonContiguousEvidence
        }
        guard payload.samples.allSatisfy({ sample in
            sample.timestampS.isFinite
                && sample.rotationRateRadS.x.isFinite
                && sample.rotationRateRadS.y.isFinite
                && sample.rotationRateRadS.z.isFinite
                && sample.userAccelerationG != nil
                && sample.gravityG != nil
                && sample.fusedAttitude != nil
        }) else {
            throw ValidationError.incompleteNativeEvidence
        }
        let bounds = attempt.boundaries
        guard bounds.captureStartS <= bounds.motionStartS,
              bounds.motionStartS <= bounds.motionEndS,
              bounds.motionEndS <= bounds.captureEndS else {
            throw ValidationError.invalidBoundaries
        }
        guard export.boundarySemantics == "manual-ui-markers-v1"
                || export.boundarySemantics == "manual-capture-auto-primary-burst-v2" else {
            throw ValidationError.invalidBoundarySemantics
        }
        let replay = ReplayBuilder.buildFrames(payload: payload, boundaries: bounds)
        guard replay.count == payload.samples.count,
              zip(replay, replay.dropFirst()).allSatisfy({ $0.timestampMs < $1.timestampMs }) else {
            throw ValidationError.unreplayableEvidence
        }
        return export
    }

    nonisolated static func validateDataset(_ data: Data) throws -> DebugMotionDatasetExportV1 {
        let dataset: DebugMotionDatasetExportV1
        do {
            dataset = try JSONDecoder().decode(DebugMotionDatasetExportV1.self, from: data)
        } catch {
            throw ValidationError.malformedExport
        }
        guard dataset.format == "kamikaze.labelled-motion-dataset.v1" else {
            throw ValidationError.unsupportedFormat
        }
        guard !dataset.captures.isEmpty else { throw ValidationError.emptyDataset }

        var attemptIDs = Set<String>()
        for capture in dataset.captures {
            switch capture.label.outcome {
            case .landed, .missed, .noAttempt:
                break
            case .unclear, .calibration:
                throw ValidationError.unclassifiedDatasetCapture
            }
            guard attemptIDs.insert(capture.capture.attempt.id).inserted else {
                throw ValidationError.duplicateAttemptID
            }
            _ = try validateExport(try encodedJSON(capture))
        }
        return dataset
    }

    nonisolated static func exportClassifiedDataset(
        from sourceDirectory: URL? = nil
    ) throws -> DebugSavedDatasetExport? {
        let directory = try sourceDirectory ?? captureDirectory()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasSuffix(".kamikaze-motion-v3.json") }

        let captures = try files.compactMap { url -> DebugMotionCaptureExportV1? in
            let capture = try validateExport(Data(contentsOf: url))
            switch capture.label.outcome {
            case .landed, .missed, .noAttempt:
                return capture
            case .unclear, .calibration:
                return nil
            }
        }.sorted {
            let lhs = $0.capture.attempt
            let rhs = $1.capture.attempt
            if lhs.recordedAtISO8601 == rhs.recordedAtISO8601 {
                return lhs.id < rhs.id
            }
            return lhs.recordedAtISO8601 < rhs.recordedAtISO8601
        }

        guard !captures.isEmpty else { return nil }
        let dataset = DebugMotionDatasetExportV1(captures: captures)
        let data = try encodedJSON(dataset)
        let decoded = try JSONDecoder().decode(DebugMotionDatasetExportV1.self, from: data)
        guard decoded.format == dataset.format,
              decoded.captures.count == captures.count else {
            throw ValidationError.malformedExport
        }
        for capture in decoded.captures {
            _ = try validateExport(try encodedJSON(capture))
        }

        let url = directory.appending(path: "kamikaze-labelled-dataset-v1.json")
        try data.write(to: url, options: .atomic)
        let countsByTrick = Dictionary(grouping: captures) { $0.label.expectedTrickID }
            .mapValues(\.count)
        return DebugSavedDatasetExport(
            exportURL: url,
            captureCount: captures.count,
            countsByTrick: countsByTrick
        )
    }

    nonisolated enum ValidationError: Error, Equatable, Sendable {
        case malformedExport
        case unsupportedFormat
        case schemaMismatch
        case attemptIDMismatch
        case sampleCountMismatch
        case checksumMismatch
        case emptySamples
        case nonContiguousEvidence
        case incompleteNativeEvidence
        case invalidBoundaries
        case invalidBoundarySemantics
        case unreplayableEvidence
        case emptyDataset
        case unclassifiedDatasetCapture
        case duplicateAttemptID
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
