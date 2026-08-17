import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct AxisCalibrationAnalyzerTests {
    @Test func mapsThreeUniqueDominantAxesAndDirections() throws {
        let profile = try #require(AxisCalibrationAnalyzer.analyze(
            [
                observation(.width, Vector3(x: 88, y: 4, z: 2)),
                observation(.longEdge, Vector3(x: 3, y: -92, z: 5)),
                observation(.screen, Vector3(x: 1, y: 4, z: 95)),
            ],
            deviceName: "Test iPhone",
            operatingSystemVersion: "iOS 26",
            profileID: "profile-test",
            createdAt: Date(timeIntervalSince1970: 0)
        ))

        #expect(profile.isReliable)
        #expect(profile.mappings.map(\.rawAxis) == [.x, .y, .z])
        #expect(profile.mappings.map(\.sign) == [1, -1, 1])
        #expect(profile.confidence > 0.85)
    }

    @Test func rejectsCrossTalkAndDuplicateAxesAsReliableProfile() throws {
        let profile = try #require(AxisCalibrationAnalyzer.analyze(
            [
                observation(.width, Vector3(x: 70, y: 65, z: 0)),
                observation(.longEdge, Vector3(x: 80, y: 5, z: 0)),
                observation(.screen, Vector3(x: 0, y: 3, z: 90)),
            ],
            deviceName: "Test iPhone",
            operatingSystemVersion: "iOS 26"
        ))

        #expect(!profile.isReliable)
        #expect(profile.confidence < 0.70)
    }

    @Test func requiresEveryKnownMovement() {
        #expect(AxisCalibrationAnalyzer.analyze(
            [observation(.width, Vector3(x: 90, y: 0, z: 0))],
            deviceName: "Test iPhone",
            operatingSystemVersion: "iOS 26"
        ) == nil)
    }

    private func observation(
        _ axis: CalibrationLogicalAxis,
        _ degrees: Vector3
    ) -> AxisCalibrationObservation {
        AxisCalibrationObservation(
            logicalAxis: axis,
            integratedDegrees: degrees,
            durationMs: 1_000,
            sampleCount: 100
        )
    }
}
