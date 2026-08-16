import CoreMotion
import KamikazeMotionCore
import Observation

/// Lightweight live-attitude feed for preview stages (Setup). 30 Hz device
/// motion, no capture, no detector, no persistence — the phone on the stage
/// simply mirrors the phone in your hand. Zeroes itself on the first sample
/// so the stage starts neutral.
@MainActor
@Observable
final class AttitudePreviewModel {
    private let manager = CMMotionManager()
    private(set) var attitude = Quaternion.identity
    private var zero: Quaternion?

    var relativeAttitude: Quaternion {
        guard let zero else { return attitude }
        return QuaternionMath.relative(from: zero, to: attitude)
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let quaternion = motion?.attitude.quaternion else { return }
            let value = Quaternion(
                w: quaternion.w,
                x: quaternion.x,
                y: quaternion.y,
                z: quaternion.z
            )
            Task { @MainActor [weak self] in
                self?.receive(value)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    func zeroPose() {
        zero = attitude
    }

    private func receive(_ value: Quaternion) {
        attitude = value
        if zero == nil {
            zero = value
        }
    }
}
