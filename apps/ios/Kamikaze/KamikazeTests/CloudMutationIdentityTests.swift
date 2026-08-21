import Testing
@testable import Kamikaze

struct CloudMutationIdentityTests {
    @Test func sameSummaryProducesStableMutationIdentity() {
        let summary = makeSummary(score: 81)
        #expect(CloudMutationIdentity.attempt(summary) == CloudMutationIdentity.attempt(summary))
        #expect(CloudMutationIdentity.attempt(summary).count < 160)
    }

    @Test func revisedSummaryProducesNewMutationIdentity() {
        #expect(CloudMutationIdentity.attempt(makeSummary(score: 81)) != CloudMutationIdentity.attempt(makeSummary(score: 82)))
    }

    @Test func deleteIdentityIsStableAndBounded() {
        let first = CloudMutationIdentity.deleteAttempt("attempt-123")
        let second = CloudMutationIdentity.deleteAttempt("attempt-123")
        #expect(first == second)
        #expect(first.count < 160)
    }

    private func makeSummary(score: Int) -> CloudAttemptSummaryV1 {
        CloudAttemptSummaryV1(
            attemptID: "attempt-123",
            recordedAtISO8601: "2026-08-21T12:00:00Z",
            trickID: "phoneFlip",
            recognitionStatus: "recognized",
            motionDurationMs: 720,
            fit: 0.91,
            gameScore: score,
            scoreVersion: "score-v1",
            analysisVersion: "analysis-v1",
            catalogVersion: "catalog-v1",
            sampleCount: 72
        )
    }
}
