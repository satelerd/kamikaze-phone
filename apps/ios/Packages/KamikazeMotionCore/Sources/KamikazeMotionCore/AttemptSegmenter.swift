import Foundation

public enum AttemptSegmentationPhase: String, Codable, Equatable, Sendable {
    case idle
    case armed
    case motion
    case settling
    case complete
}

public enum AttemptSegmentationTrigger: String, Codable, Equatable, Sendable {
    case freefall
    case gyro
    case manual
}

public struct AttemptSegmenterConfiguration: Equatable, Sendable {
    public var freefallEnterG = 0.28
    public var freefallExitG = 0.55
    public var minimumFreefallMs = 25.0
    public var stableAccelMinG = 0.68
    public var stableAccelMaxG = 1.38
    public var stableGyroRadS = 90.0 * .pi / 180
    public var settleMs = 180.0
    public var maximumMotionMs = 2_600.0
    public var maximumAttemptMs = 3_600.0
    public var preRollMs = 300.0
    public var gyroEnterRadS = 180.0 * .pi / 180
    public var gyroExitRadS = 72.0 * .pi / 180
    public var minimumGyroBurstMs = 18.0
    public var postRollMs = 220.0
    public var refractoryMs = 350.0

    public init() {}
}

public struct SegmentedAttemptV3: Equatable, Sendable {
    public let captureMode: CaptureMode
    public let trigger: AttemptSegmentationTrigger
    public let boundaries: AttemptBoundariesV3
    public let samples: [MotionSampleV3]
    public let timedOut: Bool

    public init(
        captureMode: CaptureMode,
        trigger: AttemptSegmentationTrigger,
        boundaries: AttemptBoundariesV3,
        samples: [MotionSampleV3],
        timedOut: Bool
    ) {
        self.captureMode = captureMode
        self.trigger = trigger
        self.boundaries = boundaries
        self.samples = samples
        self.timedOut = timedOut
    }
}

public struct AttemptSegmenterSnapshot: Equatable, Sendable {
    public let phase: AttemptSegmentationPhase
    public let captureMode: CaptureMode?
    public let trigger: AttemptSegmentationTrigger?
    public let sampleCount: Int
    public let lastAttempt: SegmentedAttemptV3?

    public init(
        phase: AttemptSegmentationPhase,
        captureMode: CaptureMode?,
        trigger: AttemptSegmentationTrigger?,
        sampleCount: Int,
        lastAttempt: SegmentedAttemptV3?
    ) {
        self.phase = phase
        self.captureMode = captureMode
        self.trigger = trigger
        self.sampleCount = sampleCount
        self.lastAttempt = lastAttempt
    }
}

/// Finds truthful capture and motion boundaries. It never names or scores the
/// motion; classification consumes `SegmentedAttemptV3` later.
public struct AttemptSegmenter: Sendable {
    private let configuration: AttemptSegmenterConfiguration
    private var phase: AttemptSegmentationPhase = .idle
    private var captureMode: CaptureMode?
    private var trigger: AttemptSegmentationTrigger?
    private var rollingSamples: [MotionSampleV3] = []
    private var attemptSamples: [MotionSampleV3] = []
    private var lowGStartedAtS: Double?
    private var highGyroStartedAtS: Double?
    private var quietStartedAtS: Double?
    private var stableStartedAtS: Double?
    private var motionStartS: Double?
    private var motionEndS: Double?
    private var releaseS: Double?
    private var catchS: Double?
    private var refractoryUntilS: Double?
    private var lastTimestampS: Double?
    private var lastAttempt: SegmentedAttemptV3?

    public init(configuration: AttemptSegmenterConfiguration = .init()) {
        self.configuration = configuration
    }

    @discardableResult
    public mutating func arm(mode: CaptureMode = .auto) -> AttemptSegmenterSnapshot {
        clearAttempt(keepingRefractory: true)
        phase = .armed
        captureMode = mode
        return snapshot
    }

    @discardableResult
    public mutating func cancel() -> AttemptSegmenterSnapshot {
        clearAttempt(keepingRefractory: true)
        phase = .idle
        return snapshot
    }

    @discardableResult
    public mutating func process(_ sample: MotionSampleV3) -> AttemptSegmenterSnapshot {
        lastTimestampS = sample.timestampS

        switch phase {
        case .armed:
            pushRollingSample(sample)
            if captureMode == .manual {
                beginMotion(at: sample.timestampS, releaseS: nil, trigger: .manual)
            } else if refractoryUntilS.map({ sample.timestampS >= $0 }) ?? true {
                detectAutomaticStart(sample)
            }
        case .motion:
            appendAttemptSample(sample)
            if trigger != .manual { detectMotionEnd(sample) }
        case .settling:
            appendAttemptSample(sample)
            detectSettled(sample)
        case .idle, .complete:
            break
        }

        enforceTimeout(at: sample.timestampS)
        return snapshot
    }

    @discardableResult
    public mutating func finishManualCapture() -> AttemptSegmenterSnapshot {
        guard captureMode == .manual,
              phase == .motion || phase == .settling,
              let timestampS = lastTimestampS else {
            return snapshot
        }
        motionEndS = timestampS
        complete(at: timestampS, settledS: nil, timedOut: false)
        return snapshot
    }

    public var snapshot: AttemptSegmenterSnapshot {
        AttemptSegmenterSnapshot(
            phase: phase,
            captureMode: captureMode,
            trigger: trigger,
            sampleCount: attemptSamples.count,
            lastAttempt: lastAttempt
        )
    }

    private mutating func detectAutomaticStart(_ sample: MotionSampleV3) {
        let accelG = sample.accelerationIncludingGravityG?.magnitude ?? 1
        let gyroRadS = sample.rotationRateRadS.magnitude

        if accelG <= configuration.freefallEnterG {
            highGyroStartedAtS = nil
            lowGStartedAtS = lowGStartedAtS ?? sample.timestampS
            if let lowGStartedAtS,
               elapsedMs(from: lowGStartedAtS, to: sample.timestampS) >= configuration.minimumFreefallMs {
                beginMotion(at: lowGStartedAtS, releaseS: lowGStartedAtS, trigger: .freefall)
            }
            return
        }

        lowGStartedAtS = nil
        guard gyroRadS >= configuration.gyroEnterRadS else {
            highGyroStartedAtS = nil
            return
        }
        highGyroStartedAtS = highGyroStartedAtS ?? sample.timestampS
        if let highGyroStartedAtS,
           elapsedMs(from: highGyroStartedAtS, to: sample.timestampS) >= configuration.minimumGyroBurstMs {
            let earliestS = rollingSamples.first?.timestampS ?? highGyroStartedAtS
            beginMotion(
                at: max(earliestS, highGyroStartedAtS - 0.12),
                releaseS: nil,
                trigger: .gyro
            )
        }
    }

    private mutating func beginMotion(
        at timestampS: Double,
        releaseS: Double?,
        trigger: AttemptSegmentationTrigger
    ) {
        phase = .motion
        self.trigger = trigger
        motionStartS = timestampS
        self.releaseS = releaseS
        motionEndS = nil
        catchS = nil
        quietStartedAtS = nil
        stableStartedAtS = nil
        attemptSamples = rollingSamples.filter {
            $0.timestampS >= timestampS - configuration.preRollMs / 1_000
        }
    }

    private mutating func detectMotionEnd(_ sample: MotionSampleV3) {
        guard let motionStartS else { return }
        let accelG = sample.accelerationIncludingGravityG?.magnitude ?? 1
        let gyroRadS = sample.rotationRateRadS.magnitude
        let durationMs = elapsedMs(from: motionStartS, to: sample.timestampS)

        if trigger == .gyro {
            let dynamic = gyroRadS >= configuration.gyroExitRadS || accelG < 0.55 || accelG > 1.55
            if dynamic, durationMs < configuration.maximumMotionMs {
                quietStartedAtS = nil
                return
            }
            quietStartedAtS = quietStartedAtS ?? sample.timestampS
            guard let quietStartedAtS,
                  elapsedMs(from: quietStartedAtS, to: sample.timestampS) >= configuration.postRollMs
                    || durationMs >= configuration.maximumMotionMs else {
                return
            }
            beginSettling(motionEndedAt: quietStartedAtS, catchS: nil)
            return
        }

        if accelG >= configuration.freefallExitG || durationMs >= configuration.maximumMotionMs {
            beginSettling(motionEndedAt: sample.timestampS, catchS: sample.timestampS)
        }
    }

    private mutating func beginSettling(motionEndedAt: Double, catchS: Double?) {
        phase = .settling
        motionEndS = motionEndedAt
        self.catchS = catchS
        stableStartedAtS = nil
    }

    private mutating func detectSettled(_ sample: MotionSampleV3) {
        let accelG = sample.accelerationIncludingGravityG?.magnitude ?? 1
        let gyroRadS = sample.rotationRateRadS.magnitude
        let resumed: Bool
        if trigger == .gyro {
            resumed = gyroRadS >= configuration.gyroExitRadS || accelG < 0.55 || accelG > 1.55
        } else {
            resumed = accelG < configuration.freefallEnterG
        }
        if resumed {
            phase = .motion
            motionEndS = nil
            catchS = nil
            quietStartedAtS = nil
            stableStartedAtS = nil
            return
        }

        let stable = accelG >= configuration.stableAccelMinG
            && accelG <= configuration.stableAccelMaxG
            && gyroRadS <= configuration.stableGyroRadS
        if stable {
            stableStartedAtS = stableStartedAtS ?? sample.timestampS
        } else {
            stableStartedAtS = nil
        }

        guard let stableStartedAtS, let motionEndS else { return }
        let stableLongEnough = elapsedMs(from: stableStartedAtS, to: sample.timestampS)
            >= configuration.settleMs
        let postRollComplete = elapsedMs(from: motionEndS, to: sample.timestampS)
            >= configuration.postRollMs
        if stableLongEnough, postRollComplete {
            complete(at: sample.timestampS, settledS: sample.timestampS, timedOut: false)
        }
    }

    private mutating func enforceTimeout(at timestampS: Double) {
        guard phase == .motion || phase == .settling,
              captureMode != .manual,
              let motionStartS,
              elapsedMs(from: motionStartS, to: timestampS) >= configuration.maximumAttemptMs else {
            return
        }
        motionEndS = motionEndS ?? timestampS
        complete(at: timestampS, settledS: nil, timedOut: true)
    }

    private mutating func complete(at timestampS: Double, settledS: Double?, timedOut: Bool) {
        guard let captureMode,
              let trigger,
              let motionStartS,
              let motionEndS,
              let captureStartS = attemptSamples.first?.timestampS else {
            return
        }
        let attempt = SegmentedAttemptV3(
            captureMode: captureMode,
            trigger: trigger,
            boundaries: AttemptBoundariesV3(
                captureStartS: captureStartS,
                captureEndS: timestampS,
                motionStartS: motionStartS,
                motionEndS: motionEndS,
                releaseS: releaseS,
                catchS: catchS,
                settledS: settledS
            ),
            samples: attemptSamples,
            timedOut: timedOut
        )
        lastAttempt = attempt
        phase = .complete
        refractoryUntilS = timestampS + configuration.refractoryMs / 1_000
    }

    private mutating func pushRollingSample(_ sample: MotionSampleV3) {
        rollingSamples.append(sample)
        let triggerLookbackMs = max(
            configuration.minimumFreefallMs + 50,
            configuration.minimumGyroBurstMs + 120
        )
        let cutoffS = sample.timestampS
            - (configuration.preRollMs + triggerLookbackMs) / 1_000
        rollingSamples.removeAll { $0.timestampS < cutoffS }
    }

    private mutating func appendAttemptSample(_ sample: MotionSampleV3) {
        guard attemptSamples.last?.sequence != sample.sequence else { return }
        attemptSamples.append(sample)
    }

    private mutating func clearAttempt(keepingRefractory: Bool) {
        phase = .idle
        captureMode = nil
        trigger = nil
        rollingSamples = []
        attemptSamples = []
        lowGStartedAtS = nil
        highGyroStartedAtS = nil
        quietStartedAtS = nil
        stableStartedAtS = nil
        motionStartS = nil
        motionEndS = nil
        releaseS = nil
        catchS = nil
        lastTimestampS = nil
        lastAttempt = nil
        if !keepingRefractory { refractoryUntilS = nil }
    }

    private func elapsedMs(from startS: Double, to endS: Double) -> Double {
        max(0, endS - startS) * 1_000
    }
}
