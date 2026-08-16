import Testing
@testable import KamikazeMotionCore

struct MotionBurstRefinerTests {
    @Test func isolatesStrongestBurstInsideLooseManualMarkers() {
        var samples: [MotionSampleV3] = []
        for index in 0 ... 300 {
            let time = Double(index) * 0.01
            let rate: Double
            if time >= 1.1, time <= 1.7 {
                rate = 900 * .pi / 180
            } else if time >= 2.55, time <= 2.59 {
                rate = 220 * .pi / 180
            } else {
                rate = 20 * .pi / 180
            }
            samples.append(sample(sequence: UInt64(index), timestampS: time, zRate: rate))
        }

        let burst = MotionBurstRefiner.primaryBurst(
            samples: samples,
            markerStartS: 0.3,
            markerEndS: 2.8
        )

        #expect(burst != nil)
        #expect(abs((burst?.startS ?? 0) - 1.045) < 0.011)
        #expect(abs((burst?.endS ?? 0) - 1.8) < 0.011)
        #expect((burst?.activeSampleCount ?? 0) >= 60)
    }

    @Test func returnsNilForHandlingWithoutRotationalBurst() {
        let samples = (0 ... 80).map {
            sample(sequence: UInt64($0), timestampS: Double($0) * 0.01, zRate: 30 * .pi / 180)
        }
        #expect(MotionBurstRefiner.primaryBurst(
            samples: samples,
            markerStartS: 0.1,
            markerEndS: 0.7
        ) == nil)
    }

    private func sample(sequence: UInt64, timestampS: Double, zRate: Double) -> MotionSampleV3 {
        MotionSampleV3(
            sequence: sequence,
            timestampS: timestampS,
            rotationRateRadS: Vector3(x: 0, y: 0, z: zRate),
            userAccelerationG: Vector3(x: 0, y: 0, z: 0),
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: .identity
        )
    }
}
