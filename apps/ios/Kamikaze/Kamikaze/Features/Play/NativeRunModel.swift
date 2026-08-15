import CryptoKit
import Foundation
import KamikazeMotionApple
import KamikazeMotionCore
import Observation
import UIKit

enum NativeRunPhase: Equatable {
    case ready
    case armed
    case motion
    case settling
    case result
    case unknown
    case failed(String)
}

nonisolated enum AttemptInterpretationSource: String, Equatable, Sendable {
    case detector
    case human
}

nonisolated struct AttemptIdentityAssessment: Equatable, Sendable {
    let trickID: BuiltInTrickID?
    let fit: Double?
    let recognitionStatus: TrickRecognitionStatus
    let source: AttemptInterpretationSource
}

nonisolated enum AttemptExecutionAssessment: Equatable, Sendable {
    case unverified
    case human(HumanAttemptOutcome)
}

nonisolated struct AttemptGameScore: Equatable, Sendable {
    let value: Int
    let version: String
}

nonisolated struct NativeRunEvaluation: Equatable, Sendable {
    let identity: AttemptIdentityAssessment
    let execution: AttemptExecutionAssessment
    /// Intentionally nil until execution scoring is calibrated independently
    /// from the detector's identity fit.
    let score: AttemptGameScore?
}

struct NativeRunResult: Identifiable, Sendable {
    let capture: MotionCaptureV3
    let match: TrickMatchResult
    let humanReview: HumanAttemptReview?

    init(
        capture: MotionCaptureV3,
        match: TrickMatchResult,
        humanReview: HumanAttemptReview? = nil
    ) {
        self.capture = capture
        self.match = match
        self.humanReview = humanReview
    }

    var id: String { capture.attempt.id }
    var displayName: String {
        if let reviewedTrick = humanReview?.trickID {
            return reviewedTrick.displayName
        }
        if humanReview?.outcome == .noAttempt {
            return "NO ATTEMPT"
        }
        switch match.status {
        case .recognized:
            return match.candidates.first?.definition.displayName ?? "REVIEW THROW"
        case .review:
            return "NEEDS REVIEW"
        case .unknown, .invalid:
            return "UNKNOWN THROW"
        }
    }
    var proposedName: String? {
        guard humanReview == nil, match.status == .review else { return nil }
        return match.candidates.first?.definition.displayName
    }
    var fit: Int { Int(((match.candidates.first?.presentationFit ?? 0) * 100).rounded()) }
    var displayedFitValue: Double? {
        let candidate: TrickMatchCandidate?
        if let reviewedTrick = humanReview?.trickID {
            candidate = match.candidates.first { $0.definition.id == reviewedTrick }
        } else {
            candidate = match.candidates.first
        }
        return candidate?.presentationFit
    }
    var displayedFit: Int? { displayedFitValue.map { Int(($0 * 100).rounded()) } }
    var durationMs: Int { Int((match.features?.motionDurationMs ?? 0).rounded()) }
    var evaluation: NativeRunEvaluation {
        NativeRunEvaluation(
            identity: AttemptIdentityAssessment(
                trickID: humanReview?.trickID ?? match.candidates.first?.definition.id,
                fit: displayedFitValue,
                recognitionStatus: match.status,
                source: humanReview == nil ? .detector : .human
            ),
            execution: humanReview.map { .human($0.outcome) } ?? .unverified,
            score: nil
        )
    }
    var identityLabel: String {
        evaluation.identity.source == .human ? "HUMAN CONFIRMED" : match.status.rawValue.uppercased()
    }
    var executionLabel: String {
        switch evaluation.execution {
        case .unverified: "UNVERIFIED"
        case let .human(outcome): outcome.displayName
        }
    }
    var hasConfirmedLanding: Bool { humanReview?.outcome == .landed }

    func replacingHumanReview(_ review: HumanAttemptReview) -> Self {
        Self(capture: capture, match: match, humanReview: review)
    }
}

/// UI bridge for the native vertical slice. Sensor samples are passed straight
/// to `RunProcessingEngine`; only already-reduced telemetry crosses back to
/// the main actor at roughly 20 Hz.
@MainActor
@Observable
final class NativeRunModel {
    private let source = CoreMotionSampleSource()
    private let engine = RunProcessingEngine()
    private var streamTask: Task<Void, Never>?
    private var activeStreamID: UUID?
    private var activeRunID: String?
    private let repository: FileAttemptRepository
    private let analysisRepository: FileAttemptAnalysisRepository
    private let summaryRepository: FileAttemptSummaryRepository
    private var lastPaintUptime = 0.0

    private(set) var phase: NativeRunPhase = .ready
    private(set) var attitude = Quaternion.identity
    private(set) var zeroAttitude: Quaternion?
    private(set) var measuredHz = 0.0
    private(set) var gyroDps = 0.0
    private(set) var result: NativeRunResult?

    var relativeAttitude: Quaternion {
        guard let zeroAttitude else { return attitude }
        return QuaternionMath.relative(from: zeroAttitude, to: attitude)
    }

    var canArm: Bool {
        switch phase {
        case .ready, .result, .unknown, .failed: true
        case .armed, .motion, .settling: false
        }
    }

    init() {
        let root = AttemptStorageLocation.applicationRoot()
        repository = FileAttemptRepository(rootDirectory: root)
        analysisRepository = FileAttemptAnalysisRepository(rootDirectory: root)
        summaryRepository = FileAttemptSummaryRepository(rootDirectory: root)
    }

    func start() {
        guard streamTask == nil else { return }
        guard source.isAvailable else {
            phase = .failed("Motion sensors are unavailable on this device.")
            return
        }

        let streamID = UUID()
        activeStreamID = streamID
        streamTask = Task.detached(priority: .userInitiated) { [weak self, source, engine] in
            defer {
                Task { @MainActor [weak self] in
                    self?.streamDidEnd(streamID: streamID)
                }
            }
            do {
                for try await sample in source.samples(configuration: MotionStreamConfiguration(
                    requestedFrequencyHz: 100,
                    ringBufferDurationS: 0.5,
                    timestampGapFactor: 1.5
                )) {
                    guard !Task.isCancelled else { break }
                    let event = await engine.ingest(sample)
                    await self?.receive(event)
                }
            } catch is CancellationError {
                // Expected when Play leaves the view.
            } catch {
                await self?.fail("Motion stream stopped: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        activeStreamID = nil
        activeRunID = nil
        source.stop()
        Task { await engine.cancelAll() }
        if case .armed = phase { phase = .ready }
        if case .motion = phase { phase = .ready }
        if case .settling = phase { phase = .ready }
    }

    func arm() {
        guard source.isAvailable else {
            phase = .failed("Motion sensors are unavailable on this device.")
            return
        }
        start()
        result = nil
        let runID = UUID().uuidString.lowercased()
        activeRunID = runID
        phase = .armed
        Task { [weak self] in
            guard let self else { return }
            await self.engine.arm(runID: runID)
            guard self.activeRunID == runID else {
                await self.engine.cancel(runID: runID)
                return
            }
        }
    }

    func cancel() {
        guard let runID = activeRunID else { return }
        activeRunID = nil
        result = nil
        phase = .ready
        Task { [weak self] in
            guard let self else { return }
            await self.engine.cancel(runID: runID)
        }
    }

    func zeroPose() {
        zeroAttitude = attitude
    }

    func dismissResultAndRearm() {
        result = nil
        arm()
    }

    func dismissResult() {
        result = nil
        phase = .ready
    }

    func applyHumanReview(_ review: HumanAttemptReview) async -> NativeRunResult? {
        guard let current = result else { return nil }
        let updated = current.replacingHumanReview(review)
        do {
            let record = AttemptAnalysisRecord(
                attemptID: current.id,
                result: current.match,
                humanReview: review
            )
            try await analysisRepository.save(record)
            try? await summaryRepository.upsert(AttemptSummaryV1(
                attempt: current.capture.attempt,
                analysis: record,
                timezone: .current
            ))
            guard result?.id == current.id else { return nil }
            result = updated
            return updated
        } catch {
            return nil
        }
    }

    private func receive(_ event: RunProcessingEvent) async {
        let now = ProcessInfo.processInfo.systemUptime
        let belongsToActiveRun = event.runID != nil && event.runID == activeRunID
        let phaseChanged = belongsToActiveRun && phase != event.phase
        if phaseChanged || now - lastPaintUptime >= 0.05 {
            lastPaintUptime = now
            attitude = event.attitude
            measuredHz = event.measuredHz
            gyroDps = event.gyroDps
            if belongsToActiveRun {
                phase = event.phase
            }
        }

        guard belongsToActiveRun, let completed = event.completed else { return }
        activeRunID = nil
        let nativeResult = NativeRunResult(capture: completed.capture, match: completed.match)
        result = nativeResult
        phase = completed.match.status == .unknown || completed.match.status == .invalid ? .unknown : .result
        // The complete segment is immutable. Stop collecting immediately so a
        // second throw cannot leak into this attempt's raw evidence.
        source.stop()
        streamTask?.cancel()
        streamTask = nil
        // Store after result publication: a slow filesystem must never delay
        // the catch/result moment. The raw payload is immutable and complete.
        Task { [repository, analysisRepository, summaryRepository] in
            do {
                try await repository.save(completed.capture)
                let record = AttemptAnalysisRecord(
                    attemptID: completed.capture.attempt.id,
                    result: completed.match
                )
                try await analysisRepository.save(record)
                // Best-effort: the Profile reconciler rebuilds any summary this
                // write misses, so a failure here never loses evidence.
                try? await summaryRepository.upsert(AttemptSummaryV1(
                    attempt: completed.capture.attempt,
                    analysis: record,
                    timezone: .current
                ))
            } catch {
                // The result remains available in memory. Profile exposes any
                // persistence failure when it refreshes instead of delaying
                // the catch moment here.
            }
        }
    }

    private func fail(_ message: String) {
        activeRunID = nil
        phase = .failed(message)
    }

    private func streamDidEnd(streamID: UUID) {
        guard activeStreamID == streamID else { return }
        activeStreamID = nil
        streamTask = nil
    }
}

private struct RunProcessingEvent: Sendable {
    let runID: String?
    let phase: NativeRunPhase
    let attitude: Quaternion
    let measuredHz: Double
    let gyroDps: Double
    let completed: RunProcessedAttempt?
}

private struct RunProcessedAttempt: Sendable {
    let capture: MotionCaptureV3
    let match: TrickMatchResult
}

private actor RunProcessingEngine {
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
            scoreVersion: nil
        )
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            captureMode: segmented.captureMode,
            triggerMode: segmented.trigger == .freefall ? .freefall : .gyro,
            boundaries: segmented.boundaries,
            environment: CaptureEnvironmentV3(
                device: CaptureDeviceMetadataV3(
                    modelIdentifier: nil,
                    modelName: "iPhone",
                    operatingSystemName: "iOS",
                    operatingSystemVersion: nil,
                    operatingSystemBuild: nil
                ),
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
