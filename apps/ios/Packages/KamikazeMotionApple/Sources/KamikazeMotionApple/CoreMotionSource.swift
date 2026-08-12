@preconcurrency import CoreMotion
import Foundation
import KamikazeMotionCore

public enum CoreMotionSourceError: Error, Equatable, Sendable {
    case unavailable
}

public final class CoreMotionSource: @unchecked Sendable {
    private let manager: CMMotionManager
    private let queue: OperationQueue
    private let lock = NSLock()
    private var activeToken: UUID?

    public init() {
        manager = CMMotionManager()
        queue = OperationQueue()
        queue.name = "tech.sateler.kamikaze.motion"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
    }

    public var isAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    public func frames(frequencyHz: Double = 100) -> AsyncThrowingStream<AppleMotionFrame, Error> {
        let manager = manager
        let queue = queue
        let token = UUID()

        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(16)) { continuation in
            guard manager.isDeviceMotionAvailable else {
                continuation.finish(throwing: CoreMotionSourceError.unavailable)
                return
            }

            lock.withLock { activeToken = token }
            manager.deviceMotionUpdateInterval = 1 / max(1, frequencyHz)
            manager.startDeviceMotionUpdates(
                using: .xArbitraryZVertical,
                to: queue
            ) { motion, error in
                if let error {
                    continuation.finish(throwing: error)
                    return
                }
                guard let motion else { return }

                let attitude = motion.attitude.quaternion
                let rotation = motion.rotationRate
                let acceleration = motion.userAcceleration
                let gravity = motion.gravity
                continuation.yield(AppleMotionFrame(
                    timestampS: motion.timestamp,
                    attitude: Quaternion(
                        w: attitude.w,
                        x: attitude.x,
                        y: attitude.y,
                        z: attitude.z
                    ),
                    rotationRateRadiansPerSecond: Vector3(
                        x: rotation.x,
                        y: rotation.y,
                        z: rotation.z
                    ),
                    userAccelerationG: Vector3(
                        x: acceleration.x,
                        y: acceleration.y,
                        z: acceleration.z
                    ),
                    gravityG: Vector3(
                        x: gravity.x,
                        y: gravity.y,
                        z: gravity.z
                    )
                ))
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                let shouldStop = self.lock.withLock { () -> Bool in
                    guard self.activeToken == token else { return false }
                    self.activeToken = nil
                    return true
                }
                if shouldStop {
                    manager.stopDeviceMotionUpdates()
                }
            }
        }
    }

    public func stop() {
        lock.withLock { activeToken = nil }
        manager.stopDeviceMotionUpdates()
    }
}
