import KamikazeMotionCore

public struct AppleMotionFrame: Equatable, Sendable {
    public let timestampS: Double
    public let attitude: Quaternion
    public let rotationRateRadiansPerSecond: Vector3
    public let userAccelerationG: Vector3
    public let gravityG: Vector3

    public init(
        timestampS: Double,
        attitude: Quaternion,
        rotationRateRadiansPerSecond: Vector3,
        userAccelerationG: Vector3,
        gravityG: Vector3
    ) {
        self.timestampS = timestampS
        self.attitude = attitude
        self.rotationRateRadiansPerSecond = rotationRateRadiansPerSecond
        self.userAccelerationG = userAccelerationG
        self.gravityG = gravityG
    }

    public var accelerationIncludingGravityG: Vector3 {
        Vector3(
            x: userAccelerationG.x + gravityG.x,
            y: userAccelerationG.y + gravityG.y,
            z: userAccelerationG.z + gravityG.z
        )
    }
}
