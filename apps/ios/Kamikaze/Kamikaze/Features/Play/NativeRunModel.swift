import CryptoKit
import Foundation
import KamikazeMotionApple
import KamikazeMotionCore
import Observation
import UIKit
import os

enum NativeRunPhase: Equatable {
    case ready
    case armed
    case motion
    case settling
    case result
    case unknown
    case failed(String)

    /// Reduction for the shared experience system.
    var experiencePhase: ExperiencePhase {
        switch self {
        case .ready: .idle
        case .armed: .armed
        case .motion: .motion
        case .settling: .settling
        case .result: .landed
        case .unknown, .failed: .review
        }
    }
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
/// the main actor at roughly 20 Hz. Play uses it without a target; Practice
/// passes `expectedTrickID` and reads the same result against that target.
@MainActor
@Observable
final class NativeRunModel {
    /// Practice target. Capture, segmentation and matching are identical to
    /// Play; the expectation only changes how a result is presented and which
    /// quick confirmations make sense.
    let expectedTrickID: BuiltInTrickID?

    private let source = CoreMotionSampleSource()
    private let engine = RunProcessingEngine()
    private var streamTask: Task<Void, Never>?
    private var activeStreamID: UUID?
    private var activeRunID: String?
    private let repository: FileAttemptRepository
    private let analysisRepository: FileAttemptAnalysisRepository
    private let summaryRepository: FileAttemptSummaryRepository
    private var lastPoseUptime = 0.0
    private var lastTelemetryUptime = 0.0
    /// Latest-wins mailbox between the 100 Hz sensor loop and the MainActor.
    /// Pure pose events overwrite each other here instead of queueing, so a
    /// busy UI can never back the stream up (which surfaced as the stage
    /// lagging further and further behind the hand, then looking dead).
    private struct PendingPose {
        var event: RunProcessingEvent?
        var drainScheduled = false
    }
    private let pendingPose = OSAllocatedUnfairLock(initialState: PendingPose())

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

    init(expectedTrickID: BuiltInTrickID? = nil) {
        self.expectedTrickID = expectedTrickID
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
                // Phase transitions and completion cross to the MainActor
                // awaited and in order; pure pose updates take the
                // latest-wins mailbox so this loop never waits on the UI.
                var forwardedPhase: NativeRunPhase?
                for try await sample in source.samples(configuration: MotionStreamConfiguration(
                    requestedFrequencyHz: 100,
                    ringBufferDurationS: 0.5,
                    timestampGapFactor: 1.5
                )) {
                    guard !Task.isCancelled else { break }
                    let event = await engine.ingest(sample)
                    if event.completed != nil || event.phase != forwardedPhase {
                        forwardedPhase = event.phase
                        await self?.receive(event)
                    } else {
                        self?.postLatestPose(event)
                    }
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
        // The completed run stopped the stream to seal its evidence; bring it
        // back so the stage keeps tracking the hand after Close.
        start()
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

    /// Sensor-loop side of the mailbox. Nonisolated: it must never hop actors
    /// itself — it only overwrites the pending event and, at most once per
    /// drain cycle, schedules the MainActor task that empties the mailbox.
    nonisolated private func postLatestPose(_ event: RunProcessingEvent) {
        let schedule = pendingPose.withLock { state -> Bool in
            state.event = event
            guard !state.drainScheduled else { return false }
            state.drainScheduled = true
            return true
        }
        guard schedule else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            while let event = self.takePendingPose() {
                // Not authoritative: a stale mailbox event must never roll
                // the phase back behind the awaited transition lane.
                await self.receive(event, phaseAuthoritative: false)
            }
        }
    }

    nonisolated private func takePendingPose() -> RunProcessingEvent? {
        pendingPose.withLock { state in
            guard let event = state.event else {
                state.drainScheduled = false
                return nil
            }
            state.event = nil
            return event
        }
    }

    private func receive(_ event: RunProcessingEvent, phaseAuthoritative: Bool = true) async {
        let now = ProcessInfo.processInfo.systemUptime
        let belongsToActiveRun = event.runID != nil && event.runID == activeRunID
        let phaseChanged = phaseAuthoritative && belongsToActiveRun && phase != event.phase
        // Two publish gates on purpose. The pose tracks the hand, so it goes
        // out near display cadence (~50 Hz from the 100 Hz stream) — a single
        // shared 20 Hz gate here is what made the live stage feel choppy.
        // Numeric telemetry is for reading, not tracking: 8 Hz keeps digits
        // legible and spares its observers the high-frequency invalidation.
        // Only views that read a property re-evaluate, so screens isolate the
        // pose reads in `LiveRunStage`.
        if phaseChanged || now - lastPoseUptime >= 1.0 / 60.0 {
            lastPoseUptime = now
            attitude = event.attitude
        }
        if phaseChanged || now - lastTelemetryUptime >= 0.125 {
            lastTelemetryUptime = now
            measuredHz = event.measuredHz
            gyroDps = event.gyroDps
        }
        if phaseChanged {
            phase = event.phase
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
