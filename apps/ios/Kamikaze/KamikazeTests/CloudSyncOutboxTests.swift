import Foundation
import Testing
@testable import Kamikaze

struct CloudSyncOutboxTests {
    @Test func enqueueIsIdempotentForSameMutationID() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = FileCloudOutbox(rootDirectory: directory)
        let operation = CloudSyncOperation.deleteAttemptSummary(attemptID: "attempt-001")

        let first = try await outbox.enqueue(operation, mutationID: "delete-001")
        let second = try await outbox.enqueue(operation, mutationID: "delete-001")
        #expect(first == second)
        #expect(try await outbox.count() == 1)

        await #expect(throws: CloudOutboxError.mutationIDCollision) {
            _ = try await outbox.enqueue(
                CloudSyncOperation.deleteMedia(mediaKey: "media-001"),
                mutationID: "delete-001"
            )
        }
    }

    @Test func outboxPersistsAndRetriesWithBoundedBackoff() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let operation = CloudSyncOperation.deleteMedia(mediaKey: "media-001")
        let initialDate = Date(timeIntervalSince1970: 100)
        let policy = CloudRetryPolicy(baseDelay: 5, maximumDelay: 20)
        let outbox = FileCloudOutbox(rootDirectory: directory)
        _ = try await outbox.enqueue(operation, mutationID: "media-001", enqueuedAt: initialDate)

        let failed = try await outbox.markFailure(
            mutationID: "media-001",
            error: "temporary network failure",
            now: initialDate,
            policy: policy
        )
        #expect(failed?.attemptCount == 1)
        #expect(failed?.nextAttemptAt == initialDate.addingTimeInterval(5))
        #expect(try await outbox.ready(now: initialDate).isEmpty)
        #expect(try await outbox.ready(now: initialDate.addingTimeInterval(5)).count == 1)

        let reloaded = FileCloudOutbox(rootDirectory: directory)
        let entries = try await reloaded.all()
        #expect(entries.count == 1)
        #expect(entries[0].mutationID == "media-001")
        #expect(entries[0].lastError == "temporary network failure")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeCloudOutboxTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
