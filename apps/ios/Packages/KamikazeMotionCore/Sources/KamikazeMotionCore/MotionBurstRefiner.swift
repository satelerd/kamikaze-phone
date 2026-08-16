import Foundation

public struct MotionBurstWindow: Equatable, Sendable {
    public let startS: Double
    public let endS: Double
    public let peakGyroDps: Double
    public let activeSampleCount: Int

    public init(startS: Double, endS: Double, peakGyroDps: Double, activeSampleCount: Int) {
        self.startS = startS
        self.endS = endS
        self.peakGyroDps = peakGyroDps
        self.activeSampleCount = activeSampleCount
    }
}

/// Locates the strongest rotational burst inside intentionally loose manual
/// UI markers. It never removes raw samples: it only refines the motion
/// boundaries used by feature extraction and replay progress.
public enum MotionBurstRefiner {
    public static func primaryBurst(
        samples: [MotionSampleV3],
        markerStartS: Double,
        markerEndS: Double,
        enterGyroDps: Double = 180,
        mergeGapMs: Double = 90,
        leadingPaddingMs: Double = 55,
        trailingPaddingMs: Double = 100
    ) -> MotionBurstWindow? {
        let candidates = samples.filter {
            $0.timestampS >= markerStartS && $0.timestampS <= markerEndS
        }
        guard candidates.count >= 2 else { return nil }

        struct Run {
            var firstS: Double
            var lastS: Double
            var peakDps: Double
            var energy: Double
            var count: Int
        }

        let threshold = enterGyroDps * .pi / 180
        let maximumGapS = mergeGapMs / 1_000
        var runs: [Run] = []
        var current: Run?
        var previousActiveS: Double?

        for sample in candidates {
            let magnitude = sample.rotationRateRadS.magnitude
            guard magnitude >= threshold else { continue }
            if let previousActiveS, sample.timestampS - previousActiveS <= maximumGapS,
               var active = current {
                let delta = sample.timestampS - previousActiveS
                active.lastS = sample.timestampS
                active.peakDps = max(active.peakDps, magnitude * 180 / .pi)
                active.energy += magnitude * max(0, delta)
                active.count += 1
                current = active
            } else {
                if let current { runs.append(current) }
                current = Run(
                    firstS: sample.timestampS,
                    lastS: sample.timestampS,
                    peakDps: magnitude * 180 / .pi,
                    energy: magnitude * 0.01,
                    count: 1
                )
            }
            previousActiveS = sample.timestampS
        }
        if let current { runs.append(current) }

        guard let primary = runs.max(by: {
            if $0.energy == $1.energy { return $0.peakDps < $1.peakDps }
            return $0.energy < $1.energy
        }), primary.count >= 2 else { return nil }

        return MotionBurstWindow(
            startS: max(markerStartS, primary.firstS - leadingPaddingMs / 1_000),
            endS: min(markerEndS, primary.lastS + trailingPaddingMs / 1_000),
            peakGyroDps: primary.peakDps,
            activeSampleCount: primary.count
        )
    }
}
