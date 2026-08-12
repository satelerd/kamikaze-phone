import Foundation

public enum ReplayBuilder {
    private static let earthGravity = 9.80665

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
}
