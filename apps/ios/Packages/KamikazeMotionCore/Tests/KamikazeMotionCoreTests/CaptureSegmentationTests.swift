import Foundation
import Testing
@testable import KamikazeMotionCore

private final class ControlledMotionSampleSource: MotionSampleSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<MotionSampleV3, Error>.Continuation?

    func samples(
        configuration _: MotionStreamConfiguration
    ) -> AsyncThrowingStream<MotionSampleV3, Error> {
        AsyncThrowingStream(bufferingPolicy: .unbounded) { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    func yield(_ sample: MotionSampleV3) {
        lock.withLock { continuation }?.yield(sample)
    }

    func stop() {
        let continuation = lock.withLock { () -> AsyncThrowingStream<MotionSampleV3, Error>.Continuation? in
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.finish()
    }
}

private struct FixtureSampleClock {
    var timestampS: Double
    var sequence: UInt64 = 0
    let intervalS: Double

    init(startS: Double = 100, frequencyHz: Double = 100) {
        timestampS = startS
        intervalS = 1 / frequencyHz
    }

    mutating func sample(accelG: Double = 1, gyroRadS: Vector3 = .testZero) -> MotionSampleV3 {
        defer {
            sequence += 1
            timestampS += intervalS
        }
        return MotionSampleV3(
            sequence: sequence,
            timestampS: timestampS,
            rotationRateRadS: gyroRadS,
            userAccelerationG: Vector3(x: 0, y: 0, z: accelG - 1),
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: .identity
        )
    }
}

@Suite("Motion capture actor")
struct MotionCaptureActorTests {
    @Test("preserves every source sample and reports sequence and timestamp gaps")
    func preservesEvidenceAndReportsGaps() async throws {
        let samples = [
            makeSample(sequence: 10, timestampS: 1),
            makeSample(sequence: 11, timestampS: 1.01),
            makeSample(sequence: 14, timestampS: 1.05, quality: [.sequenceGapBefore, .timestampGapBefore]),
        ]
        let actor = MotionCaptureActor(source: FixtureMotionSampleSource(samples: samples))
        let events = await actor.start(configuration: MotionStreamConfiguration(
            requestedFrequencyHz: 100,
            ringBufferDurationS: 0.02,
            timestampGapFactor: 1.5
        ))
        var finished: MotionCaptureSession?
        for try await event in events {
            if case let .finished(session) = event { finished = session }
        }

        let session = try #require(finished)
        #expect(session.samples == samples)
        #expect(session.termination == .sourceEnded)
        #expect(session.diagnostics.receivedSampleCount == 3)
        #expect(session.diagnostics.missingSequenceCount == 2)
        #expect(session.diagnostics.timestampGapCount == 1)
        #expect(session.diagnostics.sourceFlaggedGapCount == 1)
        #expect(abs((session.diagnostics.measuredFrequencyHz ?? 0) - 40) < 0.001)
        let snapshot = await actor.snapshot()
        #expect(snapshot.isRunning == false)
        #expect(snapshot.ringBuffer.map(\.sequence) == [14])
        #expect(snapshot.lastSession == session)
    }

    @Test("lifecycle cancellation finishes the stream and keeps received evidence")
    func lifecycleCancellation() async throws {
        let source = ControlledMotionSampleSource()
        let actor = MotionCaptureActor(source: source)
        let events = await actor.start()
        var iterator = events.makeAsyncIterator()
        source.yield(makeSample(sequence: 0, timestampS: 1))
        let first = try await iterator.next()
        guard case .sample = first else {
            Issue.record("Expected the buffered fixture sample before cancellation")
            return
        }

        await actor.cancel(reason: .lifecycle)
        var finished: MotionCaptureSession?
        while let event = try await iterator.next() {
            if case let .finished(session) = event { finished = session }
        }

        let session = try #require(finished)
        #expect(session.termination == .cancelled(.lifecycle))
        #expect(session.samples.count == 1)
        #expect(await actor.snapshot().isRunning == false)
    }

    private func makeSample(
        sequence: UInt64,
        timestampS: Double,
        quality: MotionSampleQualityFlags = []
    ) -> MotionSampleV3 {
        MotionSampleV3(
            sequence: sequence,
            timestampS: timestampS,
            rotationRateRadS: .testZero,
            userAccelerationG: .testZero,
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: .identity,
            qualityFlags: quality
        )
    }
}

@Suite("Attempt segmenter v3")
struct AttemptSegmenterTests {
    @Test("low fast gyro motion closes with pre-roll, post-roll and truthful boundaries")
    func lowFastClosure() throws {
        var clock = FixtureSampleClock()
        var segmenter = AttemptSegmenter()
        segmenter.arm()

        for _ in 0..<30 { segmenter.process(clock.sample()) }
        for _ in 0..<40 {
            segmenter.process(clock.sample(
                accelG: 0.75,
                gyroRadS: Vector3(x: 0, y: 15, z: 0)
            ))
        }
        for _ in 0..<55 { segmenter.process(clock.sample()) }

        let snapshot = segmenter.snapshot
        let attempt = try #require(snapshot.lastAttempt)
        #expect(snapshot.phase == .complete)
        #expect(attempt.trigger == .gyro)
        #expect(attempt.captureMode == .auto)
        #expect(attempt.timedOut == false)
        #expect(attempt.boundaries.releaseS == nil)
        #expect(attempt.boundaries.catchS == nil)
        #expect(attempt.boundaries.settledS != nil)
        #expect(attempt.boundaries.captureStartS < attempt.boundaries.motionStartS)
        #expect(attempt.boundaries.motionStartS < attempt.boundaries.motionEndS)
        #expect(attempt.boundaries.captureEndS - attempt.boundaries.motionEndS >= 0.39)
        #expect(attempt.samples.count > 70)
    }

    @Test("active automatic motion cannot remain stuck past timeout")
    func automaticTimeout() throws {
        var clock = FixtureSampleClock(startS: 200)
        var segmenter = AttemptSegmenter()
        segmenter.arm()

        for _ in 0..<4 {
            segmenter.process(clock.sample(gyroRadS: Vector3(x: 8, y: 0, z: 0)))
        }
        for _ in 0..<400 {
            segmenter.process(clock.sample(gyroRadS: Vector3(x: 2, y: 0, z: 0)))
        }

        let attempt = try #require(segmenter.snapshot.lastAttempt)
        #expect(segmenter.snapshot.phase == .complete)
        #expect(attempt.trigger == .gyro)
        #expect(attempt.timedOut)
        #expect(attempt.boundaries.settledS == nil)
        #expect(attempt.boundaries.captureEndS - attempt.boundaries.motionStartS >= 3.6)
        #expect(attempt.boundaries.captureEndS - attempt.boundaries.motionStartS < 3.62)
    }

    @Test("freefall capture preserves physical release and catch boundaries")
    func freefallClosure() throws {
        var clock = FixtureSampleClock(startS: 250)
        var segmenter = AttemptSegmenter()
        segmenter.arm()

        for _ in 0..<30 { segmenter.process(clock.sample()) }
        for _ in 0..<20 {
            segmenter.process(clock.sample(
                accelG: 0.1,
                gyroRadS: Vector3(x: 0, y: 9, z: 0)
            ))
        }
        segmenter.process(clock.sample(accelG: 2.4, gyroRadS: Vector3(x: 0, y: 4, z: 0)))
        for _ in 0..<50 { segmenter.process(clock.sample()) }

        let attempt = try #require(segmenter.snapshot.lastAttempt)
        #expect(segmenter.snapshot.phase == .complete)
        #expect(attempt.trigger == .freefall)
        #expect(attempt.boundaries.releaseS != nil)
        #expect(attempt.boundaries.catchS != nil)
        #expect(attempt.boundaries.settledS != nil)
        #expect(attempt.boundaries.releaseS == attempt.boundaries.motionStartS)
        #expect(attempt.boundaries.catchS == attempt.boundaries.motionEndS)
        #expect(attempt.boundaries.captureStartS < attempt.boundaries.releaseS ?? .infinity)
        #expect(attempt.boundaries.captureEndS > attempt.boundaries.catchS ?? -.infinity)
    }

    @Test("cancel discards an in-flight attempt without producing evidence")
    func cancellation() {
        var clock = FixtureSampleClock(startS: 300)
        var segmenter = AttemptSegmenter()
        segmenter.arm()
        for _ in 0..<4 {
            segmenter.process(clock.sample(gyroRadS: Vector3(x: 8, y: 0, z: 0)))
        }
        #expect(segmenter.snapshot.phase == .motion)

        segmenter.cancel()

        #expect(segmenter.snapshot.phase == .idle)
        #expect(segmenter.snapshot.sampleCount == 0)
        #expect(segmenter.snapshot.lastAttempt == nil)
    }

    @Test("ordinary stable handling stays armed and keeps only bounded pre-roll")
    func negativeStableHandling() {
        var clock = FixtureSampleClock(startS: 400)
        var segmenter = AttemptSegmenter()
        segmenter.arm()

        for _ in 0..<1_000 {
            segmenter.process(clock.sample(
                accelG: 1,
                gyroRadS: Vector3(x: 0.1, y: 0.08, z: 0.12)
            ))
        }

        #expect(segmenter.snapshot.phase == .armed)
        #expect(segmenter.snapshot.sampleCount == 0)
        #expect(segmenter.snapshot.lastAttempt == nil)
    }

    @Test("manual capture uses explicit start and stop without automatic timeout")
    func manualCapture() throws {
        var clock = FixtureSampleClock(startS: 500)
        var segmenter = AttemptSegmenter()
        segmenter.arm(mode: .manual)
        for _ in 0..<500 {
            segmenter.process(clock.sample(gyroRadS: Vector3(x: 0, y: 4, z: 0)))
        }
        #expect(segmenter.snapshot.phase == .motion)

        segmenter.finishManualCapture()

        let attempt = try #require(segmenter.snapshot.lastAttempt)
        #expect(attempt.captureMode == .manual)
        #expect(attempt.trigger == .manual)
        #expect(attempt.timedOut == false)
        #expect(attempt.boundaries.releaseS == nil)
        #expect(attempt.boundaries.catchS == nil)
        #expect(attempt.samples.count == 500)
    }
}

@Suite("Native fused-attitude replay")
struct NativeReplayBuilderTests {
    @Test("uses stored attitude with capture timestamps and motion progress")
    func fusedAttitudeReplay() throws {
        let quaternions = [
            Quaternion.identity,
            Quaternion(w: cos(.pi / 8), x: 0, y: sin(.pi / 8), z: 0),
            Quaternion(w: cos(.pi / 4), x: 0, y: sin(.pi / 4), z: 0),
            Quaternion(w: -cos(3 * .pi / 8), x: 0, y: -sin(3 * .pi / 8), z: 0),
        ]
        let samples = quaternions.enumerated().map { index, quaternion in
            MotionSampleV3(
                sequence: UInt64(index),
                timestampS: 10 + Double(index) * 0.1,
                rotationRateRadS: Vector3(x: 0, y: .pi, z: 0),
                userAccelerationG: .testZero,
                gravityG: Vector3(x: 0, y: 0, z: 1),
                fusedAttitude: quaternion
            )
        }
        let payload = MotionSamplePayloadV3(attemptID: "replay", samples: samples)
        let boundaries = AttemptBoundariesV3(
            captureStartS: 10,
            captureEndS: 10.3,
            motionStartS: 10.1,
            motionEndS: 10.2,
            releaseS: nil,
            catchS: nil,
            settledS: 10.3
        )

        let frames = ReplayBuilder.buildFrames(payload: payload, boundaries: boundaries)

        #expect(frames.count == 4)
        #expect(frames.map(\.timestampMs).elementsEqual([0, 100, 200, 300], by: {
            abs($0 - $1) < 0.000_001
        }))
        #expect(frames.map(\.progress).elementsEqual([0, 0, 1, 1], by: {
            abs($0 - $1) < 0.000_001
        }))
        #expect(frames.first?.quaternion == .identity)
        #expect(zip(frames, frames.dropFirst()).allSatisfy { previous, current in
            previous.quaternion.w * current.quaternion.w
                + previous.quaternion.x * current.quaternion.x
                + previous.quaternion.y * current.quaternion.y
                + previous.quaternion.z * current.quaternion.z >= 0
        })
        #expect(abs((frames.last?.gyroDps ?? 0) - 180) < 0.000_001)
        #expect(frames.last?.accelG == 1)
    }

    @Test("returns no frames when legacy evidence lacks fused attitude")
    func missingAttitudeIsNotFabricated() {
        let payload = MotionSamplePayloadV3(attemptID: "legacy", samples: [])
        let boundaries = AttemptBoundariesV3(
            captureStartS: 0,
            captureEndS: 1,
            motionStartS: 0.2,
            motionEndS: 0.8,
            releaseS: nil,
            catchS: nil,
            settledS: nil
        )

        #expect(ReplayBuilder.buildFrames(payload: payload, boundaries: boundaries).isEmpty)
    }
}

private extension Vector3 {
    static let testZero = Vector3(x: 0, y: 0, z: 0)
}
