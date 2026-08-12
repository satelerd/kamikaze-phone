import Foundation

public enum QuaternionMath {
    public static func normalized(_ quaternion: Quaternion) -> Quaternion {
        let norm = sqrt(
            quaternion.w * quaternion.w +
            quaternion.x * quaternion.x +
            quaternion.y * quaternion.y +
            quaternion.z * quaternion.z
        )
        guard norm > 0 else { return .identity }
        return Quaternion(
            w: quaternion.w / norm,
            x: quaternion.x / norm,
            y: quaternion.y / norm,
            z: quaternion.z / norm
        )
    }

    public static func multiplied(_ left: Quaternion, _ right: Quaternion) -> Quaternion {
        Quaternion(
            w: left.w * right.w - left.x * right.x - left.y * right.y - left.z * right.z,
            x: left.w * right.x + left.x * right.w + left.y * right.z - left.z * right.y,
            y: left.w * right.y - left.x * right.z + left.y * right.w + left.z * right.x,
            z: left.w * right.z + left.x * right.y - left.y * right.x + left.z * right.w
        )
    }

    public static func integrated(
        _ quaternion: Quaternion,
        rotationRateDps: Vector3,
        deltaTimeS: Double
    ) -> Quaternion {
        guard deltaTimeS > 0 else { return quaternion }
        let radiansPerSecond = Vector3(
            x: rotationRateDps.x * .pi / 180,
            y: rotationRateDps.y * .pi / 180,
            z: rotationRateDps.z * .pi / 180
        )
        let angularSpeed = radiansPerSecond.magnitude
        let angle = angularSpeed * deltaTimeS
        guard angle != 0, angularSpeed > 0 else { return quaternion }

        let halfAngle = angle / 2
        let scale = sin(halfAngle) / angularSpeed
        let delta = Quaternion(
            w: cos(halfAngle),
            x: radiansPerSecond.x * scale,
            y: radiansPerSecond.y * scale,
            z: radiansPerSecond.z * scale
        )
        return normalized(multiplied(quaternion, delta))
    }

    public static func interpolated(
        from: Quaternion,
        to: Quaternion,
        progress: Double
    ) -> Quaternion {
        let amount = min(1, max(0, progress))
        var target = to
        var dot = from.w * to.w + from.x * to.x + from.y * to.y + from.z * to.z

        if dot < 0 {
            dot = -dot
            target = Quaternion(w: -to.w, x: -to.x, y: -to.y, z: -to.z)
        }

        if dot > 0.9995 {
            return normalized(Quaternion(
                w: from.w + (target.w - from.w) * amount,
                x: from.x + (target.x - from.x) * amount,
                y: from.y + (target.y - from.y) * amount,
                z: from.z + (target.z - from.z) * amount
            ))
        }

        let angle = acos(min(1, max(-1, dot)))
        let denominator = sin(angle)
        let fromWeight = sin((1 - amount) * angle) / denominator
        let toWeight = sin(amount * angle) / denominator
        return normalized(Quaternion(
            w: from.w * fromWeight + target.w * toWeight,
            x: from.x * fromWeight + target.x * toWeight,
            y: from.y * fromWeight + target.y * toWeight,
            z: from.z * fromWeight + target.z * toWeight
        ))
    }
}
