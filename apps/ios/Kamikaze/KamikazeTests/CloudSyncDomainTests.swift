import Foundation
import Testing
@testable import Kamikaze

struct CloudSyncDomainTests {
    @Test func operationArgumentsOmitOptionalNulls() throws {
        let summary = CloudAttemptSummaryV1(
            attemptID: "attempt-001",
            recordedAtISO8601: "2026-08-20T12:00:00Z",
            recognitionStatus: "recognized",
            motionDurationMs: 240,
            analysisVersion: "analysis-v1",
            catalogVersion: "catalog-v1",
            sampleCount: 42
        )
        let operation = CloudSyncOperation.upsertAttemptSummary(summary)
        let arguments = try operation.arguments(mutationID: "m-001")

        #expect(arguments["mutationID"] == .string("m-001"))
        #expect(arguments["attemptID"] == .string("attempt-001"))
        #expect(arguments["humanOutcome"] == nil)
        #expect(arguments["fit"] == nil)
        #expect(arguments["sampleCount"] == .number(42))
        #expect(operation.functionName == "attemptSummaries:upsert")
    }

    @Test func jsonValueRoundTripsNestedArguments() throws {
        let value: CloudJSONValue = .object([
            "name": .string("RIDER"),
            "enabled": .bool(true),
            "values": .array([.number(1), .null]),
        ])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(CloudJSONValue.self, from: data)
        #expect(decoded == value)
        #expect((value.foundationValue as? [String: Any])?["name"] as? String == "RIDER")
    }

    @Test func directSummaryProjectionPreservesFields() {
        let cloud = CloudAttemptSummaryV1(
            attemptID: "local-001",
            recordedAtISO8601: "2026-08-20T12:00:00Z",
            timezoneIdentifier: "America/Santiago",
            trickID: "phone-flip",
            recognitionStatus: "recognized",
            humanOutcome: nil,
            motionDurationMs: 312,
            fit: 0.92,
            gameScore: 87,
            scoreVersion: "score-v1",
            analysisVersion: "analysis-v1",
            catalogVersion: "catalog-v1",
            sampleCount: 120
        )
        #expect(cloud.attemptID == "local-001")
        #expect(cloud.trickID == "phone-flip")
        #expect(cloud.fit == 0.92)
        #expect(cloud.gameScore == 87)
        #expect(cloud.schemaVersion == 1)
    }
}
