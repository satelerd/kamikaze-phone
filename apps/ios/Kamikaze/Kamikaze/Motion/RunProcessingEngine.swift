import CryptoKit
import Darwin
import Foundation
import KamikazeMotionApple
import KamikazeMotionCore

/// Shared capture-processing engine: Play and Practice both feed 100 Hz
/// samples through this actor; only reduced telemetry crosses to the UI.

struct RunProcessingEvent: Sendable {
    let runID: String?
    let phase: NativeRunPhase
    let attitude: Quaternion
    let measuredHz: Double
    let gyroDps: Double
    let completed: RunProcessedAttempt?
}

struct RunProcessedAttempt: Sendable {
    let capture: MotionCaptureV3
    let match: TrickMatchResult
}

actor RunProcessingEngine {
    private var segmenter = AttemptSegmenter()
    private let matcher = TrickMatcher()
    private let catalog = TrickCatalog.provisional(gripHand: .right)
    private var previousTimestampS: Double?
    private var measuredHz = 0.0
    private var activeRunID: String?
    private var completedCurrentRun = false

    func arm(runID: String) {
        _ = segmenter.arm(mode: .auto)
        activeRunID = runID
        completedCurrentRun = false
    }

    func cancel(runID: String) {
        guard activeRunID == runID else { return }
        cancelAll()
    }

    func cancelAll() {
        _ = segmenter.cancel()
        activeRunID = nil
        completedCurrentRun = false
    }

    func ingest(_ sample: MotionSampleV3) -> RunProcessingEvent {
        if let previousTimestampS {
            let interval = sample.timestampS - previousTimestampS
            if interval > 0 {
                let instantaneous = 1 / interval
                measuredHz = measuredHz == 0 ? instantaneous : measuredHz * 0.88 + instantaneous * 0.12
            }
        }
        previousTimestampS = sample.timestampS

        let snapshot = segmenter.process(sample)
        let phase = Self.presentationPhase(snapshot.phase)
        let completed: RunProcessedAttempt?
        if let attempt = snapshot.lastAttempt,
           activeRunID != nil,
           !completedCurrentRun {
            completedCurrentRun = true
            let match = matcher.match(attempt: attempt, catalog: catalog)
            completed = makeCapture(from: attempt, match: match)
        } else {
            completed = nil
        }
        return RunProcessingEvent(
            runID: activeRunID,
            phase: completed == nil ? phase : Self.resultPhase(match: completed!.match),
            attitude: sample.fusedAttitude ?? .identity,
            measuredHz: measuredHz,
            gyroDps: sample.rotationRateRadS.magnitude * 180 / .pi,
            completed: completed
        )
    }

    private func makeCapture(
        from segmented: SegmentedAttemptV3,
        match: TrickMatchResult
    ) -> RunProcessedAttempt? {
        let id = UUID().uuidString.lowercased()
        let payload = MotionSamplePayloadV3(attemptID: id, samples: segmented.samples)
        guard let encoded = try? canonicalJSON(payload) else { return nil }
        let rawReference = RawSampleReferenceV3(
            relativePath: "raw/\(id).samples.v3.json",
            encoding: .json,
            payloadSchemaVersion: MotionSchemaV3.version,
            sampleCount: segmented.samples.count,
            checksum: SHA256.hash(data: encoded).map { String(format: "%02x", $0) }.joined()
        )
        let versions = ProcessingVersionsV3(
            calibrationProfileID: nil,
            calibrationVersion: nil,
            detectorVersion: "attempt-segmenter-v3",
            analysisVersion: match.policyVersion,
            scoreVersion: GameScoreEngine.version
        )
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            captureMode: segmented.captureMode,
            triggerMode: segmented.trigger == .freefall ? .freefall : .gyro,
            boundaries: segmented.boundaries,
            environment: CaptureEnvironmentV3(
                device: Self.deviceMetadata(),
                gripHand: .right,
                orientation: .portrait,
                referenceFrame: .xArbitraryZVertical,
                requestedFrequencyHz: 100,
                measuredFrequencyHz: measuredHz > 0 ? measuredHz : nil
            ),
            versions: versions,
            rawSamples: rawReference,
            importedExpoAnalysis: nil
        )
        return RunProcessedAttempt(capture: MotionCaptureV3(attempt: attempt, samplePayload: payload), match: match)
    }

    private func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// Foundation/Darwin-only so the processing actor never reaches into a
    /// MainActor-isolated UIKit singleton. Future datasets can now be grouped
    /// by real hardware and OS instead of the old generic "iPhone" value.
    private static func deviceMetadata() -> CaptureDeviceMetadataV3 {
        CaptureDeviceMetadataV3(
            modelIdentifier: machineIdentifier(),
            modelName: "iPhone",
            operatingSystemName: "iOS",
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            operatingSystemBuild: operatingSystemBuild()
        )
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

    private static func presentationPhase(_ phase: AttemptSegmentationPhase) -> NativeRunPhase {
        switch phase {
        case .idle: .ready
        case .armed: .armed
        case .motion: .motion
        case .settling: .settling
        case .complete: .result
        }
    }

    private static func resultPhase(match: TrickMatchResult) -> NativeRunPhase {
        match.status == .unknown || match.status == .invalid ? .unknown : .result
    }
}
