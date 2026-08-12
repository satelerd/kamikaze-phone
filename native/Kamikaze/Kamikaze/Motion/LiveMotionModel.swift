import Foundation
import KamikazeMotionApple
import KamikazeMotionCore
import Observation

@MainActor
@Observable
final class LiveMotionModel {
    enum Status: Equatable {
        case idle
        case running
        case unavailable
        case failed(String)
    }

    private let source = CoreMotionSource()
    private var streamTask: Task<Void, Never>?
    private var zeroAttitude: Quaternion?
    private var previousTimestampS: Double?
    private var smoothedHz = 0.0

    private(set) var status: Status = .idle
    private(set) var attitude = Quaternion.identity
    private(set) var measuredHz = 0.0
    private(set) var rotationRate = Vector3(x: 0, y: 0, z: 0)
    private(set) var accelerationG = Vector3(x: 0, y: 0, z: 1)

    var relativeAttitude: Quaternion {
        guard let zeroAttitude else { return attitude }
        return QuaternionMath.relative(from: zeroAttitude, to: attitude)
    }

    func start() {
        guard streamTask == nil else { return }
        guard source.isAvailable else {
            status = .unavailable
            return
        }

        status = .running
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await frame in source.frames(frequencyHz: 100) {
                    guard !Task.isCancelled else { break }
                    ingest(frame)
                }
            } catch is CancellationError {
                // Expected when the view disappears.
            } catch {
                if let sourceError = error as? CoreMotionSourceError,
                   sourceError == .unavailable {
                    status = .unavailable
                } else {
                    status = .failed(error.localizedDescription)
                }
            }
            streamTask = nil
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        source.stop()
        previousTimestampS = nil
        smoothedHz = 0
        measuredHz = 0
        if status == .running { status = .idle }
    }

    func zeroPose() {
        zeroAttitude = attitude
    }

    func clearZeroPose() {
        zeroAttitude = nil
    }

    private func ingest(_ frame: AppleMotionFrame) {
        if zeroAttitude == nil {
            zeroAttitude = frame.attitude
        }
        attitude = frame.attitude
        rotationRate = frame.rotationRateRadiansPerSecond
        accelerationG = frame.accelerationIncludingGravityG

        if let previousTimestampS {
            let delta = frame.timestampS - previousTimestampS
            if delta > 0 {
                let instantaneous = 1 / delta
                smoothedHz = smoothedHz == 0
                    ? instantaneous
                    : smoothedHz * 0.88 + instantaneous * 0.12
                measuredHz = smoothedHz
            }
        }
        previousTimestampS = frame.timestampS
    }
}
