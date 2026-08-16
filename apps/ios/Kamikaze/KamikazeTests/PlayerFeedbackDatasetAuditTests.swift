import CryptoKit
import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct PlayerFeedbackDatasetAuditTests {
    @Test func importedNativeDatasetKeepsGroundTruthAndRawEvidence() throws {
        let data = try Data(contentsOf: datasetURL)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let dataset = try CapturePersistenceCodec.decode(PlayerFeedbackDatasetV1.self, from: data)

        #expect(hash == "4534d39236a87c1a10098b38bc7d530913af8aee9c2434d8b8d8a368ca9f9748")
        #expect(dataset.format == "kamikaze.player-feedback.v1")
        #expect(dataset.captures.count == 36)
        #expect(dataset.captures.reduce(0) { $0 + $1.capture.samplePayload.samples.count } == 6_574)
        #expect(dataset.captures.count { $0.humanReview.outcome == .landed } == 34)
        #expect(dataset.captures.count { $0.humanReview.outcome == .missed } == 2)
    }

    @Test func doublePhoneFlipIsDevelopmentEvidenceNotDetectorHoldout() throws {
        let dataset = try CapturePersistenceCodec.decode(
            PlayerFeedbackDatasetV1.self,
            from: Data(contentsOf: datasetURL)
        )
        let doubles = dataset.captures.filter { $0.humanReview.trickID == .doublePhoneFlip }
        let rotations = try doubles.map { try #require($0.machineResult.features).signedRotationDegrees.y }
        let durations = try doubles.map { try #require($0.machineResult.features).motionDurationMs }

        #expect(doubles.count == 2)
        #expect(doubles.allSatisfy { $0.humanReview.outcome == .landed })
        #expect(rotations.allSatisfy { (930 ... 955).contains($0) })
        #expect(durations.allSatisfy { (1_600 ... 1_760).contains($0) })
        // Both were absent from v0.2 and correctly remained Unknown. They may
        // seed a candidate reference, but cannot validate that candidate.
        #expect(doubles.allSatisfy { $0.machineResult.status == .unknown })
    }

    private var datasetURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KamikazeTests
            .deletingLastPathComponent() // Kamikaze
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent() // repository root
            .appending(path: "fixtures/motion/v3/datasets/player-feedback-2026-08-16.json")
    }
}
