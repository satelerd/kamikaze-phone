@preconcurrency import CoreMotion
import Foundation
import KamikazeMotionCore

public enum CoreMotionSampleSourceError: Error, Equatable, Sendable {
    case bufferOverflow
}

/// Schema-v3 Core Motion adapter. The legacy `CoreMotionSource` remains intact
/// until the app switches to MotionCaptureActor.
public final class CoreMotionSampleSource: MotionSampleSource, @unchecked Sendable {
    private struct StreamState {
        var continuation: AsyncThrowingStream<MotionSampleV3, Error>.Continuation?
        var previousTimestampS: Double?
        var sequence: UInt64 = 0
        var token: UUID?
    }

    private let manager: CMMotionManager
    private let queue: OperationQueue
    private let lock = NSLock()
    private var state = StreamState()

    public init() {
        manager = CMMotionManager()
        queue = OperationQueue()
        queue.name = "tech.sateler.kamikaze.motion-v3"
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
    }

    public var isAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    public func samples(
        configuration: MotionStreamConfiguration
    ) -> AsyncThrowingStream<MotionSampleV3, Error> {
        let token = UUID()
        let expectedIntervalS = 1 / max(1, configuration.requestedFrequencyHz)

        return AsyncThrowingStream(bufferingPolicy: .unbounded) { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            guard manager.isDeviceMotionAvailable else {
                continuation.finish(throwing: CoreMotionSourceError.unavailable)
                return
            }

            let previous = lock.withLock { () -> AsyncThrowingStream<MotionSampleV3, Error>.Continuation? in
                let previous = state.continuation
                state = StreamState(continuation: continuation, token: token)
                return previous
            }
            previous?.finish()

            manager.deviceMotionUpdateInterval = expectedIntervalS
            manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
                guard let self else { return }
                if let error {
                    finish(token: token, throwing: error)
                    return
                }
                guard let motion else { return }

                let sample = lock.withLock { () -> MotionSampleV3? in
                    guard state.token == token else { return nil }
                    var flags: MotionSampleQualityFlags = []
                    if let previousTimestampS = state.previousTimestampS {
                        let intervalS = motion.timestamp - previousTimestampS
                        if intervalS == 0 { flags.insert(.timestampDuplicate) }
                        if intervalS < 0 { flags.insert(.timestampNonMonotonic) }
                        if intervalS > expectedIntervalS * configuration.timestampGapFactor {
                            flags.insert(.timestampGapBefore)
                        }
                    }
                    let attitude = motion.attitude.quaternion
                    let rotation = motion.rotationRate
                    let acceleration = motion.userAcceleration
                    let gravity = motion.gravity
                    let sample = MotionSampleV3(
                        sequence: state.sequence,
                        timestampS: motion.timestamp,
                        rotationRateRadS: Vector3(x: rotation.x, y: rotation.y, z: rotation.z),
                        userAccelerationG: Vector3(x: acceleration.x, y: acceleration.y, z: acceleration.z),
                        gravityG: Vector3(x: gravity.x, y: gravity.y, z: gravity.z),
                        fusedAttitude: Quaternion(w: attitude.w, x: attitude.x, y: attitude.y, z: attitude.z),
                        qualityFlags: flags
                    )
                    state.sequence &+= 1
                    state.previousTimestampS = motion.timestamp
                    return sample
                }
                guard let sample else { return }
                switch continuation.yield(sample) {
                case .enqueued:
                    break
                case .dropped:
                    // The production stream is unbounded, so this is an
                    // invariant failure rather than evidence to hide.
                    finish(token: token, throwing: CoreMotionSampleSourceError.bufferOverflow)
                case .terminated:
                    finish(token: token, throwing: nil)
                @unknown default:
                    finish(token: token, throwing: CoreMotionSampleSourceError.bufferOverflow)
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.finish(token: token, throwing: nil)
            }
        }
    }

    public func stop() {
        let continuation = lock.withLock { () -> AsyncThrowingStream<MotionSampleV3, Error>.Continuation? in
            let continuation = state.continuation
            state = StreamState()
            return continuation
        }
        manager.stopDeviceMotionUpdates()
        continuation?.finish()
    }

    private func finish(token: UUID, throwing error: (any Error)?) {
        let continuation = lock.withLock { () -> AsyncThrowingStream<MotionSampleV3, Error>.Continuation? in
            guard state.token == token else { return nil }
            let continuation = state.continuation
            state = StreamState()
            return continuation
        }
        guard let continuation else { return }
        manager.stopDeviceMotionUpdates()
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
