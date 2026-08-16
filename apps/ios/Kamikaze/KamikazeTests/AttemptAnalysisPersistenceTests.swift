import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct AttemptAnalysisPersistenceTests {
    @MainActor
    @Test func analysisRevisionSurvivesReloadWithoutChangingRawEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeAnalysisPersistenceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = AttemptAnalysisRecord(
            attemptID: "attempt-001",
            result: TrickMatchResult(
                status: .review,
                policyVersion: "policy-test",
                catalogVersion: "catalog-test",
                features: nil,
                featureIssues: [.timestampGap],
                candidates: []
            ),
            analyzedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let first = FileAttemptAnalysisRepository(rootDirectory: directory)
        try await first.save(expected)

        let reloaded = FileAttemptAnalysisRepository(rootDirectory: directory)
        let actual = try await reloaded.load(attemptID: expected.attemptID)
        #expect(actual == expected)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "raw").path))
    }

    @MainActor
    @Test func matcherRefreshCannotEraseHumanReview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeHumanReviewPersistenceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileAttemptAnalysisRepository(rootDirectory: directory)
        let machineResult = makeResult(policy: "policy-1")
        let review = HumanAttemptReview(
            trickID: .phoneFlip,
            outcome: .missed,
            notes: "Under-rotated",
            reviewedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        try await repository.save(AttemptAnalysisRecord(
            attemptID: "attempt-reviewed",
            result: machineResult,
            humanReview: review
        ))

        // A later matcher revision writes only machine evidence.
        try await repository.save(AttemptAnalysisRecord(
            attemptID: "attempt-reviewed",
            result: makeResult(policy: "policy-2")
        ))

        let loaded = try #require(await repository.load(attemptID: "attempt-reviewed"))
        #expect(loaded.result.policyVersion == "policy-2")
        #expect(loaded.humanReview == review)
    }

    @MainActor
    @Test func loadsLegacyV1RecordWithoutInventingHumanReview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeLegacyAnalysisTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let analysisDirectory = directory.appending(path: "analysis")
        try FileManager.default.createDirectory(at: analysisDirectory, withIntermediateDirectories: true)

        let current = AttemptAnalysisRecord(
            attemptID: "legacy-001",
            result: makeResult(policy: "legacy-policy")
        )
        let encoded = try CapturePersistenceCodec.encode(current)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 1
        object.removeValue(forKey: "humanReview")
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try legacyData.write(
            to: analysisDirectory.appending(path: "legacy-001.analysis-v1.json")
        )

        let repository = FileAttemptAnalysisRepository(rootDirectory: directory)
        let loaded = try #require(await repository.load(attemptID: "legacy-001"))
        #expect(loaded.schemaVersion == 1)
        #expect(loaded.humanReview == nil)
        #expect(loaded.result.policyVersion == "legacy-policy")
    }

    private func makeResult(policy: String) -> TrickMatchResult {
        TrickMatchResult(
            status: .review,
            policyVersion: policy,
            catalogVersion: "catalog-test",
            features: nil,
            featureIssues: [],
            candidates: []
        )
    }
}
