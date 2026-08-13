import Foundation

public enum MotionFeatureAnalysis {
    /// Rule/feature contract version. Increment whenever a feature definition changes.
    public static let version = "motion-features-v0.1-provisional"
}

public enum MotionFeatureIssue: String, Codable, Equatable, Sendable {
    case invalidBoundaries
    case insufficientMotionSamples
    case nonFiniteEvidence
    case nonMonotonicTimestamp
    case timedOutSegmentation
    case timestampGap
    case sequenceGap
    case fusedAttitudeUnavailable
    case partialFusedAttitude
    case catchBoundaryUnavailable
}

public struct MotionFeatureExtraction: Codable, Equatable, Sendable {
    public let features: MotionFeatures?
    public let issues: [MotionFeatureIssue]

    public init(features: MotionFeatures?, issues: [MotionFeatureIssue]) {
        self.features = features
        self.issues = issues
    }

    public var isValid: Bool { features != nil }
}

/// Unit-explicit, deterministic measurements derived from a segmented attempt.
/// These values are evidence for matching; none is a calibrated probability.
public struct MotionFeatures: Codable, Equatable, Sendable {
    public let analysisVersion: String
    public let motionDurationMs: Double
    public let signedRotationDegrees: Vector3
    public let angularPathDegrees: Vector3
    public let totalAngularPathDegrees: Double
    public let fusedAttitudeRotationDegrees: Vector3?
    public let gyroFusedAgreement: Double?
    public let fusedComparisonSampleCount: Int
    public let peakGyroDps: Double
    public let minimumAccelerationG: Double?
    public let peakAccelerationG: Double?
    public let peakCatchAccelerationG: Double?
    public let postCatchStability: Double?
    public let dominantAxisPurity: Double
    public let rotationEfficiency: Double

    public init(
        analysisVersion: String = MotionFeatureAnalysis.version,
        motionDurationMs: Double,
        signedRotationDegrees: Vector3,
        angularPathDegrees: Vector3,
        totalAngularPathDegrees: Double,
        fusedAttitudeRotationDegrees: Vector3?,
        gyroFusedAgreement: Double?,
        fusedComparisonSampleCount: Int,
        peakGyroDps: Double,
        minimumAccelerationG: Double?,
        peakAccelerationG: Double?,
        peakCatchAccelerationG: Double?,
        postCatchStability: Double?,
        dominantAxisPurity: Double,
        rotationEfficiency: Double
    ) {
        self.analysisVersion = analysisVersion
        self.motionDurationMs = motionDurationMs
        self.signedRotationDegrees = signedRotationDegrees
        self.angularPathDegrees = angularPathDegrees
        self.totalAngularPathDegrees = totalAngularPathDegrees
        self.fusedAttitudeRotationDegrees = fusedAttitudeRotationDegrees
        self.gyroFusedAgreement = gyroFusedAgreement
        self.fusedComparisonSampleCount = fusedComparisonSampleCount
        self.peakGyroDps = peakGyroDps
        self.minimumAccelerationG = minimumAccelerationG
        self.peakAccelerationG = peakAccelerationG
        self.peakCatchAccelerationG = peakCatchAccelerationG
        self.postCatchStability = postCatchStability
        self.dominantAxisPurity = dominantAxisPurity
        self.rotationEfficiency = rotationEfficiency
    }
}

public enum MotionFeatureExtractor {
    public static func extract(from attempt: SegmentedAttemptV3) -> MotionFeatureExtraction {
        var issues: [MotionFeatureIssue] = []
        let boundaries = attempt.boundaries
        guard boundariesAreValid(boundaries) else {
            return MotionFeatureExtraction(features: nil, issues: [.invalidBoundaries])
        }

        let motionSamples = attempt.samples.filter {
            $0.timestampS >= boundaries.motionStartS && $0.timestampS <= boundaries.motionEndS
        }
        guard motionSamples.count >= 2 else {
            return MotionFeatureExtraction(features: nil, issues: [.insufficientMotionSamples])
        }
        guard motionSamples.allSatisfy(isFinite) else {
            return MotionFeatureExtraction(features: nil, issues: [.nonFiniteEvidence])
        }
        guard zip(motionSamples, motionSamples.dropFirst()).allSatisfy({ $0.timestampS < $1.timestampS }) else {
            return MotionFeatureExtraction(features: nil, issues: [.nonMonotonicTimestamp])
        }

        if attempt.timedOut { appendUnique(.timedOutSegmentation, to: &issues) }
        if attempt.samples.contains(where: { $0.qualityFlags.contains(.timestampGapBefore) }) {
            appendUnique(.timestampGap, to: &issues)
        }
        if attempt.samples.contains(where: { $0.qualityFlags.contains(.sequenceGapBefore) }) {
            appendUnique(.sequenceGap, to: &issues)
        }

        var signedRadians = Vector3.zero
        var pathRadians = Vector3.zero
        var fusedRadians = Vector3.zero
        var fusedErrorRadians = 0.0
        var fusedPathRadians = 0.0
        var fusedComparisonCount = 0

        for (previous, current) in zip(motionSamples, motionSamples.dropFirst()) {
            let deltaTimeS = current.timestampS - previous.timestampS
            let averageRate = average(previous.rotationRateRadS, current.rotationRateRadS)
            signedRadians = adding(signedRadians, scaled(averageRate, by: deltaTimeS))
            pathRadians = adding(pathRadians, scaled(averageAbs(
                previous.rotationRateRadS,
                current.rotationRateRadS
            ), by: deltaTimeS))

            guard let previousAttitude = previous.fusedAttitude,
                  let currentAttitude = current.fusedAttitude else { continue }
            let fusedStep = rotationVectorRadians(
                QuaternionMath.relative(from: previousAttitude, to: currentAttitude)
            )
            let gyroStep = scaled(averageRate, by: deltaTimeS)
            fusedRadians = adding(fusedRadians, fusedStep)
            fusedErrorRadians += magnitude(subtracting(gyroStep, fusedStep))
            fusedPathRadians += magnitude(fusedStep)
            fusedComparisonCount += 1
        }

        if fusedComparisonCount == 0 {
            appendUnique(.fusedAttitudeUnavailable, to: &issues)
        } else if fusedComparisonCount < motionSamples.count - 1 {
            appendUnique(.partialFusedAttitude, to: &issues)
        }

        let radiansToDegrees = 180.0 / Double.pi
        let signedDegrees = scaled(signedRadians, by: radiansToDegrees)
        let pathDegrees = scaled(pathRadians, by: radiansToDegrees)
        let totalPathDegrees = pathDegrees.x + pathDegrees.y + pathDegrees.z
        let absoluteSignedTotal = abs(signedDegrees.x) + abs(signedDegrees.y) + abs(signedDegrees.z)
        let dominantPath = max(pathDegrees.x, max(pathDegrees.y, pathDegrees.z))
        let gyroFusedAgreement: Double? = fusedComparisonCount > 0
            ? clamp(1 - fusedErrorRadians / max(fusedPathRadians, 30 * .pi / 180))
            : nil

        let accelerationValues = motionSamples.compactMap { $0.accelerationIncludingGravityG?.magnitude }
        let catchStartS = boundaries.catchS ?? boundaries.motionEndS
        let postCatchSamples = attempt.samples.filter {
            $0.timestampS >= catchStartS && $0.timestampS <= boundaries.captureEndS
        }
        if boundaries.catchS == nil { appendUnique(.catchBoundaryUnavailable, to: &issues) }
        let postCatchAccel = postCatchSamples.compactMap { $0.accelerationIncludingGravityG?.magnitude }
        let peakCatch = postCatchAccel.max()
        // Keep catch impulse and settled handling distinct: assess stability after
        // a short 40 ms handle, falling back to the available post-catch window.
        let settledWindow = postCatchSamples.filter { $0.timestampS >= catchStartS + 0.04 }
        let stability = postCatchStability(
            samples: settledWindow.isEmpty ? postCatchSamples : settledWindow
        )

        return MotionFeatureExtraction(
            features: MotionFeatures(
                motionDurationMs: (boundaries.motionEndS - boundaries.motionStartS) * 1_000,
                signedRotationDegrees: signedDegrees,
                angularPathDegrees: pathDegrees,
                totalAngularPathDegrees: totalPathDegrees,
                fusedAttitudeRotationDegrees: fusedComparisonCount > 0
                    ? scaled(fusedRadians, by: radiansToDegrees)
                    : nil,
                gyroFusedAgreement: gyroFusedAgreement,
                fusedComparisonSampleCount: fusedComparisonCount,
                peakGyroDps: (motionSamples.map { $0.rotationRateRadS.magnitude }.max() ?? 0)
                    * radiansToDegrees,
                minimumAccelerationG: accelerationValues.min(),
                peakAccelerationG: accelerationValues.max(),
                peakCatchAccelerationG: peakCatch,
                postCatchStability: stability,
                dominantAxisPurity: totalPathDegrees > 0 ? dominantPath / totalPathDegrees : 1,
                rotationEfficiency: totalPathDegrees > 0
                    ? clamp(absoluteSignedTotal / totalPathDegrees)
                    : 1
            ),
            issues: issues
        )
    }

    private static func boundariesAreValid(_ boundaries: AttemptBoundariesV3) -> Bool {
        let values = [
            boundaries.captureStartS,
            boundaries.motionStartS,
            boundaries.motionEndS,
            boundaries.captureEndS,
        ]
        return values.allSatisfy(\.isFinite)
            && boundaries.captureStartS <= boundaries.motionStartS
            && boundaries.motionStartS < boundaries.motionEndS
            && boundaries.motionEndS <= boundaries.captureEndS
    }

    private static func isFinite(_ sample: MotionSampleV3) -> Bool {
        sample.timestampS.isFinite
            && finite(sample.rotationRateRadS)
            && sample.userAccelerationG.map(finite) ?? true
            && sample.gravityG.map(finite) ?? true
            && sample.legacyAccelerationIncludingGravityG.map(finite) ?? true
            && sample.fusedAttitude.map {
                $0.w.isFinite && $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
            } ?? true
    }

    private static func postCatchStability(samples: [MotionSampleV3]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let gyroValues = samples.map(\.rotationRateRadS.magnitude)
        let accelerationValues = samples.compactMap { $0.accelerationIncludingGravityG?.magnitude }
        guard !accelerationValues.isEmpty else { return nil }
        let gyroRMS = sqrt(gyroValues.reduce(0) { $0 + $1 * $1 } / Double(gyroValues.count))
        let accelerationDeviation = accelerationValues.reduce(0) { $0 + abs($1 - 1) }
            / Double(accelerationValues.count)
        // Diagnostic normalization constants, not calibrated gameplay thresholds.
        return clamp(1 - (0.6 * gyroRMS / 2.5 + 0.4 * accelerationDeviation / 0.5))
    }

    private static func rotationVectorRadians(_ quaternion: Quaternion) -> Vector3 {
        var normalized = QuaternionMath.normalized(quaternion)
        if normalized.w < 0 {
            normalized = Quaternion(
                w: -normalized.w,
                x: -normalized.x,
                y: -normalized.y,
                z: -normalized.z
            )
        }
        let halfAngleSine = sqrt(
            normalized.x * normalized.x
                + normalized.y * normalized.y
                + normalized.z * normalized.z
        )
        guard halfAngleSine > 0.000_000_001 else { return .zero }
        let angle = 2 * atan2(halfAngleSine, min(1, max(-1, normalized.w)))
        return Vector3(
            x: normalized.x / halfAngleSine * angle,
            y: normalized.y / halfAngleSine * angle,
            z: normalized.z / halfAngleSine * angle
        )
    }

    private static func average(_ left: Vector3, _ right: Vector3) -> Vector3 {
        Vector3(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2, z: (left.z + right.z) / 2)
    }

    private static func averageAbs(_ left: Vector3, _ right: Vector3) -> Vector3 {
        Vector3(
            x: (abs(left.x) + abs(right.x)) / 2,
            y: (abs(left.y) + abs(right.y)) / 2,
            z: (abs(left.z) + abs(right.z)) / 2
        )
    }

    private static func adding(_ left: Vector3, _ right: Vector3) -> Vector3 {
        Vector3(x: left.x + right.x, y: left.y + right.y, z: left.z + right.z)
    }

    private static func subtracting(_ left: Vector3, _ right: Vector3) -> Vector3 {
        Vector3(x: left.x - right.x, y: left.y - right.y, z: left.z - right.z)
    }

    private static func scaled(_ value: Vector3, by scalar: Double) -> Vector3 {
        Vector3(x: value.x * scalar, y: value.y * scalar, z: value.z * scalar)
    }

    private static func magnitude(_ value: Vector3) -> Double {
        sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
    }

    private static func finite(_ value: Vector3) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func appendUnique(_ issue: MotionFeatureIssue, to issues: inout [MotionFeatureIssue]) {
        if !issues.contains(issue) { issues.append(issue) }
    }
}

private extension Vector3 {
    static let zero = Vector3(x: 0, y: 0, z: 0)
}
