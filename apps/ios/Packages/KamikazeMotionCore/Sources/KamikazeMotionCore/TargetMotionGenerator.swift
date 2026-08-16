import Foundation

/// Generates the idealized TARGET animation for a trick: the definition's
/// signed rotation distributed over its reference duration with a smooth
/// launch/catch easing, integrated into quaternion poses.
///
/// This is mathematics, never measurement. Frames produced here must always
/// be presented as the target and can never mix with recorded evidence.
public enum TargetMotionGenerator {
    public static let version = "target-motion-v1"

    /// Idealized replay frames for one trick.
    /// - Parameters:
    ///   - definition: the trick's authored target.
    ///   - frameRateHz: pose cadence; 60 matches display-driven playback.
    ///   - settleTailS: motionless tail after the rotation so the catch pose
    ///     reads before a looped replay restarts.
    public static func frames(
        for definition: TrickDefinition,
        frameRateHz: Double = 60,
        settleTailS: Double = 0.35
    ) -> [ReplayFrame] {
        let durationS = max(0.2, definition.referenceDurationMs / 1_000)
        guard frameRateHz > 0 else { return [] }
        let dt = 1 / frameRateHz
        let motionFrameCount = max(2, Int((durationS * frameRateHz).rounded()))
        let tailFrameCount = max(0, Int((settleTailS * frameRateHz).rounded()))

        // Angular-velocity profile ∝ sin²(π·t/T): still at release, fastest at
        // the peak, still again at the catch. Its integral over T is T/2, so
        // scaling by target/(T/2) lands exactly on the signed target rotation.
        let target = definition.targetRotationDegrees
        let scale = 2 / durationS
        var quaternion = Quaternion.identity
        var frames: [ReplayFrame] = []
        frames.reserveCapacity(motionFrameCount + tailFrameCount + 1)

        for index in 0 ... motionFrameCount {
            let t = Double(index) * dt
            let phase = min(1, t / durationS)
            let envelope = pow(sin(.pi * phase), 2) * scale
            let rateDps = Vector3(
                x: target.x * envelope,
                y: target.y * envelope,
                z: target.z * envelope
            )
            if index > 0 {
                quaternion = QuaternionMath.integrated(
                    quaternion,
                    rotationRateDps: rateDps,
                    deltaTimeS: dt
                )
            }
            frames.append(ReplayFrame(
                timestampMs: t * 1_000,
                progress: phase,
                quaternion: quaternion,
                accelG: 0,
                gyroDps: rateDps.magnitude
            ))
        }

        let motionEndMs = durationS * 1_000
        if tailFrameCount > 0, let finalPose = frames.last?.quaternion {
            for index in 1 ... tailFrameCount {
                frames.append(ReplayFrame(
                    timestampMs: motionEndMs + Double(index) * dt * 1_000,
                    progress: 1,
                    quaternion: finalPose,
                    accelG: 0,
                    gyroDps: 0
                ))
            }
        }
        return frames
    }
}
