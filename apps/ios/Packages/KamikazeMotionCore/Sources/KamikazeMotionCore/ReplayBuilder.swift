import Foundation

public enum ReplayBuilder {
    private static let earthGravity = 9.80665

    /// Builds truthful native replay poses directly from Core Motion's fused
    /// attitude. Rotation-rate integration remains analysis evidence; it is not
    /// used to fabricate orientation or vertical translation here.
    public static func buildFrames(
        payload: MotionSamplePayloadV3,
        boundaries: AttemptBoundariesV3
    ) -> [ReplayFrame] {
        let samples = payload.samples.filter {
            $0.timestampS >= boundaries.captureStartS
                && $0.timestampS <= boundaries.captureEndS
                && $0.fusedAttitude != nil
        }
        guard let first = samples.first, let originAttitude = first.fusedAttitude else {
            return []
        }

        let motionDurationS = max(0, boundaries.motionEndS - boundaries.motionStartS)
        var previousQuaternion = Quaternion.identity
        return samples.map { sample in
            let attitude = sample.fusedAttitude ?? originAttitude
            var relative = QuaternionMath.relative(from: originAttitude, to: attitude)
            if quaternionDot(previousQuaternion, relative) < 0 {
                relative = Quaternion(w: -relative.w, x: -relative.x, y: -relative.y, z: -relative.z)
            }
            previousQuaternion = relative

            let progress = motionDurationS > 0
                ? min(1, max(0, (sample.timestampS - boundaries.motionStartS) / motionDurationS))
                : 0
            return ReplayFrame(
                timestampMs: (sample.timestampS - boundaries.captureStartS) * 1_000,
                progress: progress,
                quaternion: relative,
                accelG: sample.accelerationIncludingGravityG?.magnitude ?? 0,
                gyroDps: sample.rotationRateRadS.magnitude * 180 / .pi
            )
        }
    }

    public static func buildFrames(for attempt: ExpoAttemptV2) -> [ReplayFrame] {
        let preRollS = attempt.captureMode == .manual ? 0.12 : 0
        let postRollS = 0.22
        let samples = attempt.samples.filter {
            $0.timestampS >= attempt.releaseTimestampS - preRollS &&
            $0.timestampS <= attempt.catchTimestampS + postRollS
        }
        guard let first = samples.first else { return [] }

        var quaternion = Quaternion.identity
        var previous = first
        return samples.enumerated().map { index, sample in
            if index > 0 {
                let deltaTimeS = min(0.05, max(0, sample.timestampS - previous.timestampS))
                let averageRate = Vector3(
                    x: (previous.rotationRateDps.x + sample.rotationRateDps.x) / 2,
                    y: (previous.rotationRateDps.y + sample.rotationRateDps.y) / 2,
                    z: (previous.rotationRateDps.z + sample.rotationRateDps.z) / 2
                )
                quaternion = QuaternionMath.integrated(
                    quaternion,
                    rotationRateDps: averageRate,
                    deltaTimeS: deltaTimeS
                )
            }
            previous = sample

            let progress = attempt.airtimeMs <= 0
                ? 0
                : min(1, max(0, (sample.timestampS - attempt.releaseTimestampS) * 1_000 / attempt.airtimeMs))
            return ReplayFrame(
                timestampMs: (sample.timestampS - attempt.releaseTimestampS) * 1_000,
                progress: progress,
                quaternion: quaternion,
                accelG: sample.accelerationIncludingGravity.magnitude / earthGravity,
                gyroDps: sample.rotationRateDps.magnitude
            )
        }
    }

    public static func normalized(_ frames: [ReplayFrame]) -> [ReplayFrame] {
        guard let first = frames.first else { return [] }
        let origin = first.timestampMs.isFinite ? first.timestampMs : 0
        var previous = 0.0
        let normalized = frames.enumerated().map { index, frame in
            let candidate = frame.timestampMs.isFinite ? max(0, frame.timestampMs - origin) : previous
            let timestamp = index == 0 ? 0 : max(previous, candidate)
            previous = timestamp
            return ReplayFrame(
                timestampMs: timestamp,
                progress: frame.progress,
                quaternion: frame.quaternion,
                accelG: frame.accelG,
                gyroDps: frame.gyroDps
            )
        }
        let duration = max(normalized.last?.timestampMs ?? 0, 1)
        return normalized.map {
            ReplayFrame(
                timestampMs: $0.timestampMs,
                progress: min(1, max(0, $0.timestampMs / duration)),
                quaternion: $0.quaternion,
                accelG: $0.accelG,
                gyroDps: $0.gyroDps
            )
        }
    }

    public static func sample(_ frames: [ReplayFrame], at playheadMs: Double) -> ReplayFrame {
        guard let first = frames.first else {
            return ReplayFrame(timestampMs: 0, progress: 0, quaternion: .identity, accelG: 1, gyroDps: 0)
        }
        guard frames.count > 1, playheadMs > first.timestampMs else { return first }
        guard let last = frames.last, playheadMs < last.timestampMs else { return frames.last ?? first }

        var low = 0
        var high = frames.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if frames[middle].timestampMs <= playheadMs { low = middle } else { high = middle }
        }

        let from = frames[low]
        let to = frames[high]
        let interval = max(1, to.timestampMs - from.timestampMs)
        let amount = min(1, max(0, (playheadMs - from.timestampMs) / interval))
        return ReplayFrame(
            timestampMs: playheadMs,
            progress: from.progress + (to.progress - from.progress) * amount,
            quaternion: QuaternionMath.interpolated(from: from.quaternion, to: to.quaternion, progress: amount),
            accelG: from.accelG + (to.accelG - from.accelG) * amount,
            gyroDps: from.gyroDps + (to.gyroDps - from.gyroDps) * amount
        )
    }

    private static func quaternionDot(_ left: Quaternion, _ right: Quaternion) -> Double {
        left.w * right.w + left.x * right.x + left.y * right.y + left.z * right.z
    }
}
