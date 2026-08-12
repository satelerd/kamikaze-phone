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
    private var detector = MotionDetector()

    private(set) var status: Status = .idle
    private(set) var attitude = Quaternion.identity
    private(set) var measuredHz = 0.0
    private(set) var rotationRate = Vector3(x: 0, y: 0, z: 0)
    private(set) var accelerationG = Vector3(x: 0, y: 0, z: 1)
    private(set) var detection = MotionDetectorSnapshot()
    private(set) var completedAttemptCount = 0

    var relativeAttitude: Quaternion {
        guard let zeroAttitude else { return attitude }
        return QuaternionMath.relative(from: zeroAttitude, to: attitude)
    }

    func start() {
        guard streamTask == nil else { return }
        guard source.isAvailable else {
            detection = detector.disarm()
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
                detection = detector.disarm()
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
        detection = detector.disarm()
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

    func armDetection() {
        detection = detector.arm()
    }

    func cancelDetection() {
        detection = detector.disarm()
    }

    private func ingest(_ frame: AppleMotionFrame) {
        if zeroAttitude == nil {
            zeroAttitude = frame.attitude
        }
        attitude = frame.attitude
        rotationRate = frame.rotationRateRadiansPerSecond
        accelerationG = frame.accelerationIncludingGravityG

        if detection.phase == .armed || detection.phase == .airborne || detection.phase == .settling {
            let priorPhase = detection.phase
            detection = detector.process(MotionSample(
                timestampS: frame.timestampS,
                accelerationIncludingGravity: Vector3(
                    x: accelerationG.x * 9.80665,
                    y: accelerationG.y * 9.80665,
                    z: accelerationG.z * 9.80665
                ),
                rotationRateDps: Vector3(
                    x: rotationRate.x * 180 / .pi,
                    y: rotationRate.y * 180 / .pi,
                    z: rotationRate.z * 180 / .pi
                )
            ))
            if priorPhase != .complete, detection.phase == .complete {
                completedAttemptCount += 1
            }
        }

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
