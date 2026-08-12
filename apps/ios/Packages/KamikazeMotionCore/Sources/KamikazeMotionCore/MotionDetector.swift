import Foundation

public enum DetectionPhase: String, Codable, Equatable, Sendable {
    case idle
    case armed
    case airborne
    case settling
    case complete
}

public struct MotionDetectorConfiguration: Equatable, Sendable {
    public var freefallEnterG = 0.28
    public var freefallExitG = 0.55
    public var minimumFreefallMs = 25.0
    public var stableAccelMinG = 0.68
    public var stableAccelMaxG = 1.38
    public var stableGyroDps = 90.0
    public var settleMs = 180.0
    public var maximumFlightMs = 2_600.0
    public var maximumAttemptMs = 3_600.0
    public var preReleaseMs = 300.0
    public var gyroEnterDps = 180.0
    public var gyroExitDps = 72.0
    public var minimumGyroBurstMs = 18.0
    public var postMotionMs = 220.0

    public init() {}
}

public struct MotionDetectorSnapshot: Equatable, Sendable {
    public var phase: DetectionPhase
    public var accelG: Double
    public var gyroDps: Double
    public var rotationDegrees: RotationSummary
    public var sampleCount: Int
    public var lastAttempt: ExpoAttemptV2?

    public init(
        phase: DetectionPhase = .idle,
        accelG: Double = 1,
        gyroDps: Double = 0,
        rotationDegrees: RotationSummary = RotationSummary(x: 0, y: 0, z: 0, total: 0),
        sampleCount: Int = 0,
        lastAttempt: ExpoAttemptV2? = nil
    ) {
        self.phase = phase
        self.accelG = accelG
        self.gyroDps = gyroDps
        self.rotationDegrees = rotationDegrees
        self.sampleCount = sampleCount
        self.lastAttempt = lastAttempt
    }
}

public struct MotionDetector: Sendable {
    private static let earthGravity = 9.80665

    private let configuration: MotionDetectorConfiguration
    private var phase: DetectionPhase = .idle
    private var lowGStartedAtS: Double?
    private var highGyroStartedAtS: Double?
    private var quietStartedAtS: Double?
    private var releaseTimestampS: Double?
    private var catchTimestampS: Double?
    private var stableStartedAtS: Double?
    private var lastTimestampS: Double?
    private var previousRotationRate = Vector3.zero
    private var rotationDegrees = RotationSummary.zero
    private var sampleCount = 0
    private var peakRotationDps = 0.0
    private var peakCatchG = 0.0
    private var accelG = 1.0
    private var gyroDps = 0.0
    private var triggerMode = TriggerMode.freefall
    private var rollingSamples: [MotionSample] = []
    private var attemptSamples: [MotionSample] = []
    private var lastAttempt: ExpoAttemptV2?

    public init(configuration: MotionDetectorConfiguration = .init()) {
        self.configuration = configuration
    }

    @discardableResult
    public mutating func arm() -> MotionDetectorSnapshot {
        phase = .armed
        lowGStartedAtS = nil
        highGyroStartedAtS = nil
        quietStartedAtS = nil
        releaseTimestampS = nil
        catchTimestampS = nil
        stableStartedAtS = nil
        lastTimestampS = nil
        previousRotationRate = .zero
        rotationDegrees = .zero
        sampleCount = 0
        peakRotationDps = 0
        peakCatchG = 0
        rollingSamples = []
        attemptSamples = []
        lastAttempt = nil
        return snapshot
    }

    @discardableResult
    public mutating func disarm() -> MotionDetectorSnapshot {
        phase = .idle
        lowGStartedAtS = nil
        highGyroStartedAtS = nil
        quietStartedAtS = nil
        releaseTimestampS = nil
        catchTimestampS = nil
        stableStartedAtS = nil
        lastTimestampS = nil
        previousRotationRate = .zero
        rotationDegrees = .zero
        sampleCount = 0
        peakRotationDps = 0
        peakCatchG = 0
        rollingSamples = []
        attemptSamples = []
        lastAttempt = nil
        return snapshot
    }

    @discardableResult
    public mutating func process(_ sample: MotionSample) -> MotionDetectorSnapshot {
        let deltaS = lastTimestampS.map { min(0.05, max(0, sample.timestampS - $0)) } ?? 0
        lastTimestampS = sample.timestampS
        accelG = sample.accelerationIncludingGravity.magnitude / Self.earthGravity
        gyroDps = sample.rotationRateDps.magnitude
        pushRollingSample(sample)

        switch phase {
        case .armed:
            detectRelease(at: sample.timestampS)
        case .airborne:
            appendAttemptSample(sample)
            integrateRotation(sample.rotationRateDps, deltaS: deltaS)
            sampleCount += 1
            peakRotationDps = max(peakRotationDps, gyroDps)
            peakCatchG = max(peakCatchG, accelG)
            detectCatch(at: sample.timestampS)
        case .settling:
            appendAttemptSample(sample)
            sampleCount += 1
            peakCatchG = max(peakCatchG, accelG)
            detectSettled(at: sample.timestampS)
        case .idle, .complete:
            break
        }

        previousRotationRate = sample.rotationRateDps
        enforceAttemptTimeout(at: sample.timestampS)
        return snapshot
    }

    public var snapshot: MotionDetectorSnapshot {
        MotionDetectorSnapshot(
            phase: phase,
            accelG: accelG,
            gyroDps: gyroDps,
            rotationDegrees: rotationDegrees,
            sampleCount: sampleCount,
            lastAttempt: lastAttempt
        )
    }

    private mutating func detectRelease(at timestampS: Double) {
        if accelG <= configuration.freefallEnterG {
            highGyroStartedAtS = nil
            if lowGStartedAtS == nil { lowGStartedAtS = timestampS }
            if let lowGStartedAtS,
               (timestampS - lowGStartedAtS) * 1_000 >= configuration.minimumFreefallMs {
                beginAttempt(releasedAt: lowGStartedAtS, confirmedAt: timestampS, trigger: .freefall)
            }
            return
        }

        lowGStartedAtS = nil
        guard gyroDps >= configuration.gyroEnterDps else {
            highGyroStartedAtS = nil
            return
        }
        if highGyroStartedAtS == nil {
            highGyroStartedAtS = timestampS
            return
        }
        if let highGyroStartedAtS,
           (timestampS - highGyroStartedAtS) * 1_000 >= configuration.minimumGyroBurstMs {
            let earliest = rollingSamples.first?.timestampS ?? highGyroStartedAtS
            beginAttempt(
                releasedAt: max(earliest, highGyroStartedAtS - 0.12),
                confirmedAt: timestampS,
                trigger: .gyro
            )
        }
    }

    private mutating func beginAttempt(releasedAt: Double, confirmedAt: Double, trigger: TriggerMode) {
        phase = .airborne
        triggerMode = trigger
        releaseTimestampS = releasedAt
        quietStartedAtS = nil
        attemptSamples = rollingSamples.filter {
            $0.timestampS >= releasedAt - configuration.preReleaseMs / 1_000
        }
        rebuildAirborneMetrics(through: confirmedAt)
    }

    private mutating func detectCatch(at timestampS: Double) {
        guard let releaseTimestampS else { return }
        let durationMs = (timestampS - releaseTimestampS) * 1_000

        if triggerMode == .gyro {
            let isDynamic = gyroDps >= configuration.gyroExitDps || accelG < 0.55 || accelG > 1.55
            if isDynamic, durationMs < configuration.maximumFlightMs {
                quietStartedAtS = nil
                return
            }
            if quietStartedAtS == nil {
                quietStartedAtS = timestampS
                return
            }
            if let quietStartedAtS,
               (timestampS - quietStartedAtS) * 1_000 < configuration.postMotionMs,
               durationMs < configuration.maximumFlightMs {
                return
            }
            beginSettling(at: timestampS)
            return
        }

        if accelG >= configuration.freefallExitG || durationMs >= configuration.maximumFlightMs {
            beginSettling(at: timestampS)
        }
    }

    private mutating func beginSettling(at timestampS: Double) {
        phase = .settling
        catchTimestampS = timestampS
        stableStartedAtS = nil
        peakCatchG = max(peakCatchG, accelG)
    }

    private mutating func detectSettled(at timestampS: Double) {
        if triggerMode == .gyro {
            let resumed = gyroDps >= configuration.gyroExitDps || accelG < 0.55 || accelG > 1.55
            if resumed {
                phase = .airborne
                catchTimestampS = nil
                stableStartedAtS = nil
                quietStartedAtS = nil
                return
            }
        } else if accelG < configuration.freefallEnterG {
            phase = .airborne
            catchTimestampS = nil
            stableStartedAtS = nil
            return
        }

        let isStable = accelG >= configuration.stableAccelMinG
            && accelG <= configuration.stableAccelMaxG
            && gyroDps <= configuration.stableGyroDps
        guard isStable else {
            stableStartedAtS = nil
            return
        }
        if stableStartedAtS == nil {
            stableStartedAtS = timestampS
            return
        }
        if let stableStartedAtS,
           (timestampS - stableStartedAtS) * 1_000 >= configuration.settleMs {
            completeAttempt()
        }
    }

    private mutating func enforceAttemptTimeout(at timestampS: Double) {
        guard phase == .airborne || phase == .settling, let releaseTimestampS else { return }
        guard (timestampS - releaseTimestampS) * 1_000 >= configuration.maximumAttemptMs else { return }
        catchTimestampS = catchTimestampS ?? timestampS
        completeAttempt()
    }

    private mutating func rebuildAirborneMetrics(through confirmedAtS: Double) {
        guard let releaseTimestampS else { return }
        let samples = attemptSamples.filter {
            $0.timestampS >= releaseTimestampS && $0.timestampS <= confirmedAtS
        }
        rotationDegrees = .zero
        sampleCount = samples.count
        peakRotationDps = 0

        var previous: MotionSample?
        for sample in samples {
            peakRotationDps = max(peakRotationDps, sample.rotationRateDps.magnitude)
            if let previous {
                previousRotationRate = previous.rotationRateDps
                integrateRotation(
                    sample.rotationRateDps,
                    deltaS: min(0.05, max(0, sample.timestampS - previous.timestampS))
                )
            }
            previous = sample
        }
        previousRotationRate = samples.last?.rotationRateDps ?? .zero
    }

    private mutating func integrateRotation(_ rotationRate: Vector3, deltaS: Double) {
        guard deltaS > 0 else { return }
        let average = Vector3(
            x: (previousRotationRate.x + rotationRate.x) / 2,
            y: (previousRotationRate.y + rotationRate.y) / 2,
            z: (previousRotationRate.z + rotationRate.z) / 2
        )
        rotationDegrees.x += average.x * deltaS
        rotationDegrees.y += average.y * deltaS
        rotationDegrees.z += average.z * deltaS
        rotationDegrees.total += average.magnitude * deltaS
    }

    private mutating func pushRollingSample(_ sample: MotionSample) {
        rollingSamples.append(sample)
        let cutoff = sample.timestampS
            - (
                configuration.preReleaseMs
                    + max(
                        configuration.minimumFreefallMs + 50,
                        configuration.minimumGyroBurstMs + 120
                    )
            ) / 1_000
        while rollingSamples.first?.timestampS ?? .infinity < cutoff {
            rollingSamples.removeFirst()
        }
    }

    private mutating func appendAttemptSample(_ sample: MotionSample) {
        guard attemptSamples.last?.timestampS != sample.timestampS else { return }
        attemptSamples.append(sample)
    }

    private mutating func completeAttempt() {
        guard let releaseTimestampS, let catchTimestampS else { return }
        let durationMs = max(0, (catchTimestampS - releaseTimestampS) * 1_000)
        let result = TrickClassifier.classify(rotationDegrees)
        let durationS = durationMs / 1_000
        sampleCount = attemptSamples.count
        lastAttempt = ExpoAttemptV2(
            captureMode: .auto,
            triggerMode: triggerMode,
            id: "\(UUID().uuidString)-\(Int(releaseTimestampS * 1_000))",
            source: .sensor,
            recordedAtIso: ISO8601DateFormatter().string(from: Date()),
            trick: result.trick,
            confidence: result.confidence,
            releaseTimestampS: releaseTimestampS,
            catchTimestampS: catchTimestampS,
            airtimeMs: durationMs,
            estimatedHeightM: triggerMode == .freefall
                ? Self.earthGravity * durationS * durationS / 8
                : 0,
            rotationDegrees: rotationDegrees,
            peakRotationDps: peakRotationDps,
            peakCatchG: peakCatchG,
            sampleCount: sampleCount,
            samples: attemptSamples
        )
        phase = .complete
    }
}

public enum TrickClassifier {
    public static func classify(_ rotation: RotationSummary) -> (trick: String, confidence: Double) {
        let x = abs(rotation.x) / 360
        let y = abs(rotation.y) / 360
        let z = abs(rotation.z) / 360
        let dominant = max(x, y, z)

        if y >= 0.55, z >= 0.38 {
            let sameDirection = rotation.y.sign == rotation.z.sign
            let trick = sameDirection
                ? (rotation.y >= 0 ? "360 FLIP" : "LASER FLIP")
                : "MULTI-AXIS FLIP"
            return (trick, clamped((y + z) / 2, minimum: 0.55, maximum: 0.98))
        }
        if x >= 0.55, max(y, z) >= 0.22 {
            return ("KAMIKAZE FLIP", clamped(x, minimum: 0.55, maximum: 0.96))
        }
        if x >= 0.55 {
            return (rotation.x >= 0 ? "FRONT FLIP" : "BACK FLIP", clamped(x, minimum: 0.55, maximum: 0.98))
        }
        if y >= 0.55 {
            return (rotation.y >= 0 ? "PHONE FLIP" : "REVERSE PHONE FLIP", clamped(y, minimum: 0.55, maximum: 0.98))
        }
        if z >= 0.38 {
            return (rotation.z >= 0 ? "SHUVIT +" : "SHUVIT −", clamped(z, minimum: 0.5, maximum: 0.96))
        }
        return (
            dominant >= 0.18 ? "AIR MOVE" : "STRAIGHT AIR",
            clamped(0.9 - dominant, minimum: 0.5, maximum: 0.9)
        )
    }

    private static func clamped(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value))
    }
}

private extension Vector3 {
    static let zero = Vector3(x: 0, y: 0, z: 0)
}

private extension RotationSummary {
    static let zero = RotationSummary(x: 0, y: 0, z: 0, total: 0)
}
