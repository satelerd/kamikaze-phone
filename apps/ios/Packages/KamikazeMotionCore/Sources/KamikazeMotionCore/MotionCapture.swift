import Foundation

public struct MotionStreamConfiguration: Equatable, Sendable {
    public var requestedFrequencyHz: Double
    public var ringBufferDurationS: Double
    public var timestampGapFactor: Double

    public init(
        requestedFrequencyHz: Double = 100,
        ringBufferDurationS: Double = 0.5,
        timestampGapFactor: Double = 1.5
    ) {
        self.requestedFrequencyHz = requestedFrequencyHz
        self.ringBufferDurationS = ringBufferDurationS
        self.timestampGapFactor = timestampGapFactor
    }
}

/// Platform and fixture sources implement the same evidence stream. A source
/// must assign a sequence before yielding and must finish its stream on stop.
public protocol MotionSampleSource: Sendable {
    func samples(
        configuration: MotionStreamConfiguration
    ) -> AsyncThrowingStream<MotionSampleV3, Error>

    func stop()
}

/// Deterministic source for Simulator flows and unit tests. It emits the
/// supplied timestamps exactly as stored and never sleeps on wall-clock time.
public final class FixtureMotionSampleSource: MotionSampleSource, @unchecked Sendable {
    private let fixture: [MotionSampleV3]
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<MotionSampleV3, Error>.Continuation?

    public init(samples: [MotionSampleV3]) {
        fixture = samples
    }

    public func samples(
        configuration _: MotionStreamConfiguration
    ) -> AsyncThrowingStream<MotionSampleV3, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            lock.withLock { self.continuation = continuation }
            for sample in fixture {
                guard case .enqueued = continuation.yield(sample) else { break }
            }
            lock.withLock { self.continuation = nil }
            continuation.finish()
        }
    }

    public func stop() {
        let continuation = lock.withLock { () -> AsyncThrowingStream<MotionSampleV3, Error>.Continuation? in
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.finish()
    }
}

public enum MotionCaptureCancellationReason: String, Codable, Equatable, Sendable {
    case user
    case lifecycle
    case replaced
}

public enum MotionCaptureTermination: Equatable, Sendable {
    case sourceEnded
    case stopped
    case cancelled(MotionCaptureCancellationReason)
    case failed(String)
}

public struct MotionCaptureDiagnostics: Equatable, Sendable {
    public var receivedSampleCount: Int
    public var missingSequenceCount: UInt64
    public var duplicateSequenceCount: Int
    public var outOfOrderSequenceCount: Int
    public var duplicateTimestampCount: Int
    public var nonMonotonicTimestampCount: Int
    public var timestampGapCount: Int
    public var sourceFlaggedGapCount: Int
    public var firstTimestampS: Double?
    public var lastTimestampS: Double?
    public var measuredFrequencyHz: Double?

    public init(
        receivedSampleCount: Int = 0,
        missingSequenceCount: UInt64 = 0,
        duplicateSequenceCount: Int = 0,
        outOfOrderSequenceCount: Int = 0,
        duplicateTimestampCount: Int = 0,
        nonMonotonicTimestampCount: Int = 0,
        timestampGapCount: Int = 0,
        sourceFlaggedGapCount: Int = 0,
        firstTimestampS: Double? = nil,
        lastTimestampS: Double? = nil,
        measuredFrequencyHz: Double? = nil
    ) {
        self.receivedSampleCount = receivedSampleCount
        self.missingSequenceCount = missingSequenceCount
        self.duplicateSequenceCount = duplicateSequenceCount
        self.outOfOrderSequenceCount = outOfOrderSequenceCount
        self.duplicateTimestampCount = duplicateTimestampCount
        self.nonMonotonicTimestampCount = nonMonotonicTimestampCount
        self.timestampGapCount = timestampGapCount
        self.sourceFlaggedGapCount = sourceFlaggedGapCount
        self.firstTimestampS = firstTimestampS
        self.lastTimestampS = lastTimestampS
        self.measuredFrequencyHz = measuredFrequencyHz
    }
}

public struct MotionCaptureSession: Equatable, Sendable {
    public let samples: [MotionSampleV3]
    public let diagnostics: MotionCaptureDiagnostics
    public let termination: MotionCaptureTermination

    public init(
        samples: [MotionSampleV3],
        diagnostics: MotionCaptureDiagnostics,
        termination: MotionCaptureTermination
    ) {
        self.samples = samples
        self.diagnostics = diagnostics
        self.termination = termination
    }
}

public struct MotionCaptureSnapshot: Equatable, Sendable {
    public let isRunning: Bool
    public let ringBuffer: [MotionSampleV3]
    public let diagnostics: MotionCaptureDiagnostics
    public let lastSession: MotionCaptureSession?
}

public enum MotionCaptureEvent: Equatable, Sendable {
    case sample(MotionSampleV3)
    case finished(MotionCaptureSession)
}

public enum MotionCaptureError: Error, Equatable, Sendable {
    case alreadyRunning
}

/// Owns the evidence path outside MainActor. Event delivery is separate from
/// the stored session, so a slow UI consumer cannot remove captured samples.
public actor MotionCaptureActor {
    private let source: any MotionSampleSource
    private var activeTask: Task<Void, Never>?
    private var requestedTermination: MotionCaptureTermination?
    private var configuration = MotionStreamConfiguration()
    private var capturedSamples: [MotionSampleV3] = []
    private var ringBuffer: [MotionSampleV3] = []
    private var diagnostics = MotionCaptureDiagnostics()
    private var lastSequence: UInt64?
    private var lastTimestampS: Double?
    private var positiveIntervalCount = 0
    private var positiveIntervalTotalS = 0.0
    private var lastSession: MotionCaptureSession?

    public init(source: any MotionSampleSource) {
        self.source = source
    }

    public func start(
        configuration: MotionStreamConfiguration = .init()
    ) -> AsyncThrowingStream<MotionCaptureEvent, Error> {
        guard activeTask == nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: MotionCaptureError.alreadyRunning)
            }
        }

        reset(configuration: configuration)
        let sourceStream = source.samples(configuration: configuration)
        let (events, continuation) = AsyncThrowingStream.makeStream(
            of: MotionCaptureEvent.self,
            throwing: Error.self,
            // This is a display/event channel, not the evidence store. Keeping
            // only the latest event prevents a paused UI from retaining a
            // second unbounded copy while `capturedSamples` remains complete.
            bufferingPolicy: .bufferingNewest(1)
        )
        activeTask = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            do {
                for try await sample in sourceStream {
                    try Task.checkCancellation()
                    await self.ingest(sample, continuation: continuation)
                }
                await self.finish(continuation: continuation, error: nil)
            } catch is CancellationError {
                await self.finish(continuation: continuation, error: nil)
            } catch {
                await self.finish(continuation: continuation, error: error)
            }
        }
        return events
    }

    /// Gracefully closes the source and produces a `.stopped` session.
    public func stop() {
        guard activeTask != nil else { return }
        requestedTermination = .stopped
        source.stop()
    }

    /// Lifecycle and user cancellation still preserve evidence received so far.
    public func cancel(reason: MotionCaptureCancellationReason) {
        guard let activeTask else { return }
        requestedTermination = .cancelled(reason)
        source.stop()
        activeTask.cancel()
    }

    public func snapshot() -> MotionCaptureSnapshot {
        MotionCaptureSnapshot(
            isRunning: activeTask != nil,
            ringBuffer: ringBuffer,
            diagnostics: diagnostics,
            lastSession: lastSession
        )
    }

    private func reset(configuration: MotionStreamConfiguration) {
        self.configuration = configuration
        requestedTermination = nil
        capturedSamples = []
        ringBuffer = []
        diagnostics = MotionCaptureDiagnostics()
        lastSequence = nil
        lastTimestampS = nil
        positiveIntervalCount = 0
        positiveIntervalTotalS = 0
    }

    private func ingest(
        _ sample: MotionSampleV3,
        continuation: AsyncThrowingStream<MotionCaptureEvent, Error>.Continuation
    ) {
        diagnostics.receivedSampleCount += 1
        diagnostics.firstTimestampS = diagnostics.firstTimestampS ?? sample.timestampS

        if let lastSequence {
            if sample.sequence == lastSequence {
                diagnostics.duplicateSequenceCount += 1
            } else if sample.sequence < lastSequence {
                diagnostics.outOfOrderSequenceCount += 1
            } else if sample.sequence > lastSequence + 1 {
                diagnostics.missingSequenceCount += sample.sequence - lastSequence - 1
            }
        }
        if let lastTimestampS {
            let intervalS = sample.timestampS - lastTimestampS
            if intervalS == 0 {
                diagnostics.duplicateTimestampCount += 1
            } else if intervalS < 0 {
                diagnostics.nonMonotonicTimestampCount += 1
            } else {
                positiveIntervalCount += 1
                positiveIntervalTotalS += intervalS
                let expectedIntervalS = 1 / max(1, configuration.requestedFrequencyHz)
                if intervalS > expectedIntervalS * configuration.timestampGapFactor {
                    diagnostics.timestampGapCount += 1
                }
            }
        }
        if sample.qualityFlags.contains(.timestampGapBefore)
            || sample.qualityFlags.contains(.sequenceGapBefore) {
            diagnostics.sourceFlaggedGapCount += 1
        }

        lastSequence = sample.sequence
        lastTimestampS = sample.timestampS
        diagnostics.lastTimestampS = sample.timestampS
        diagnostics.measuredFrequencyHz = positiveIntervalTotalS > 0
            ? Double(positiveIntervalCount) / positiveIntervalTotalS
            : nil

        capturedSamples.append(sample)
        ringBuffer.append(sample)
        let cutoffS = sample.timestampS - max(0, configuration.ringBufferDurationS)
        ringBuffer.removeAll { $0.timestampS < cutoffS }
        continuation.yield(.sample(sample))
    }

    private func finish(
        continuation: AsyncThrowingStream<MotionCaptureEvent, Error>.Continuation,
        error: (any Error)?
    ) {
        guard activeTask != nil else { return }
        let termination: MotionCaptureTermination
        if let requestedTermination {
            termination = requestedTermination
        } else if let error {
            termination = .failed(error.localizedDescription)
        } else {
            termination = .sourceEnded
        }
        let session = MotionCaptureSession(
            samples: capturedSamples,
            diagnostics: diagnostics,
            termination: termination
        )
        lastSession = session
        activeTask = nil
        requestedTermination = nil
        continuation.yield(.finished(session))
        if let error, case .failed = termination {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
