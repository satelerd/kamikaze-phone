import Testing
@testable import KamikazeMotionCore

@Suite("Automatic trick detector")
struct MotionDetectorTests {
    @Test("finishes a fast low shuvit without freefall")
    func lowShuvit() {
        var detector = MotionDetector()
        detector.arm()
        var timestamp = 80.0

        func sample(_ gyro: Vector3, accelG: Double = 1) -> MotionSample {
            defer { timestamp += 0.01 }
            return MotionSample(
                timestampS: timestamp,
                accelerationIncludingGravity: Vector3(x: 0, y: 0, z: accelG * 9.80665),
                rotationRateDps: gyro
            )
        }

        for _ in 0..<25 { detector.process(sample(Vector3(x: 0, y: 0, z: 0))) }
        for _ in 0..<85 { detector.process(sample(Vector3(x: 5, y: 3, z: 450))) }
        detector.process(sample(Vector3(x: 120, y: 20, z: 10), accelG: 2.2))
        for _ in 0..<55 { detector.process(sample(Vector3(x: 0, y: 0, z: 0))) }

        #expect(detector.snapshot.phase == .complete)
        #expect(detector.snapshot.lastAttempt?.triggerMode == .gyro)
        #expect(detector.snapshot.lastAttempt?.trick.contains("SHUVIT") == true)
        #expect(detector.snapshot.lastAttempt?.sampleCount == detector.snapshot.lastAttempt?.samples.count)
        #expect((detector.snapshot.lastAttempt?.peakCatchG ?? 0) > 2)
    }

    @Test("finishes a short low phone flip")
    func lowPhoneFlip() {
        var detector = MotionDetector()
        detector.arm()
        var timestamp = 120.0

        func push(count: Int, accelG: Double = 1, gyro: Vector3) {
            for _ in 0..<count {
                detector.process(MotionSample(
                    timestampS: timestamp,
                    accelerationIncludingGravity: Vector3(x: 0, y: 0, z: accelG * 9.80665),
                    rotationRateDps: gyro
                ))
                timestamp += 0.01
            }
        }

        push(count: 20, gyro: Vector3(x: 0, y: 0, z: 0))
        push(count: 40, accelG: 0.7, gyro: Vector3(x: 4, y: 900, z: 8))
        push(count: 55, gyro: Vector3(x: 0, y: 0, z: 0))

        #expect(detector.snapshot.phase == .complete)
        #expect(detector.snapshot.lastAttempt?.trick == "PHONE FLIP")
        #expect((detector.snapshot.lastAttempt?.rotationDegrees.y ?? 0) > 330)
    }

    @Test("disarming clears an in-flight capture")
    func disarmClearsCapture() {
        var detector = MotionDetector()
        detector.arm()
        var timestamp = 160.0

        for _ in 0..<8 {
            detector.process(MotionSample(
                timestampS: timestamp,
                accelerationIncludingGravity: Vector3(x: 0, y: 0, z: 9.80665),
                rotationRateDps: Vector3(x: 500, y: 0, z: 0)
            ))
            timestamp += 0.01
        }
        #expect(detector.snapshot.phase == .airborne)

        detector.disarm()

        #expect(detector.snapshot.phase == .idle)
        #expect(detector.snapshot.sampleCount == 0)
        #expect(detector.snapshot.lastAttempt == nil)
    }

    @Test("never leaves an active attempt stuck forever")
    func safetyTimeout() {
        var detector = MotionDetector()
        detector.arm()
        var timestamp = 200.0

        for index in 0..<500 {
            let gyro = index < 10
                ? Vector3(x: 500, y: 0, z: 0)
                : Vector3(x: 120, y: 0, z: 0)
            detector.process(MotionSample(
                timestampS: timestamp,
                accelerationIncludingGravity: Vector3(x: 0, y: 0, z: 9.80665),
                rotationRateDps: gyro
            ))
            timestamp += 0.01
        }

        #expect(detector.snapshot.phase == .complete)
    }
}
