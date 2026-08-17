import Foundation
import KamikazeMotionCore

/// One primary physical cue from measured features against the trick target —
/// never a wall of numbers. Axis names use the phone's body semantics:
/// Y is the flip axis, Z the spin axis, X the side axis.
nonisolated enum PracticeCoach {
    /// Rotation deltas under this threshold are not worth coaching.
    static let completionToleranceDegrees = 25.0
    /// Angular path on an axis the target keeps quiet, above which the cue
    /// calls it out.
    static let offAxisPathThresholdDegrees = 140.0
    /// Targets under this magnitude count as "quiet" axes.
    static let quietAxisThresholdDegrees = 45.0

    static func primaryCue(
        features: MotionFeatures?,
        definition: TrickDefinition
    ) -> String? {
        guard let features else { return nil }
        let target = definition.targetRotationDegrees
        let measured = features.signedRotationDegrees
        let path = features.angularPathDegrees

        // 1. Completion on the trick's dominant axis.
        let axes: [(name: String, target: Double, measured: Double, path: Double)] = [
            ("SIDE", target.x, measured.x, path.x),
            ("FLIP", target.y, measured.y, path.y),
            ("SPIN", target.z, measured.z, path.z),
        ]
        if let dominant = axes.max(by: { abs($0.target) < abs($1.target) }),
           abs(dominant.target) >= quietAxisThresholdDegrees {
            let delta = dominant.measured - dominant.target
            if abs(delta) >= completionToleranceDegrees {
                let amount = Int(abs(delta).rounded())
                // Short means the rotation stopped before the target,
                // regardless of the trick's spin direction.
                let short = abs(dominant.measured) < abs(dominant.target)
                return "\(amount)° \(short ? "SHORT" : "OVER") ON THE \(dominant.name) AXIS"
            }
        }

        // 2. Contamination on axes the target keeps quiet.
        if let noisy = axes
            .filter({ abs($0.target) < quietAxisThresholdDegrees && $0.path >= offAxisPathThresholdDegrees })
            .max(by: { $0.path < $1.path }) {
            return "TOO MUCH \(noisy.name)-AXIS MOTION"
        }

        return nil
    }

    /// One plain-language review line for Practice. Identity comes first:
    /// axis coaching is only useful after the detector saw the intended trick.
    static func reviewMessage(
        features: MotionFeatures?,
        definition: TrickDefinition,
        recognizedTrickID: BuiltInTrickID?
    ) -> String {
        guard let recognizedTrickID else {
            return "NO CLEAR MATCH — REPLAY IT, THEN TRY ONE CLEAN ROTATION"
        }
        guard recognizedTrickID == definition.id else {
            return "DETECTOR SAW \(recognizedTrickID.displayName.uppercased()) — CHECK THE TARGET DIRECTION"
        }
        return primaryCue(features: features, definition: definition)
            ?? "CLEAN ROTATION — REPEAT THAT MOTION"
    }
}
