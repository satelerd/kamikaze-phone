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
}
