import Foundation
import Testing
@testable import Kamikaze

struct CloudSyncCoordinatorTests {
    @Test func successfulForegroundSyncDrainsOnlyCompletedEntries() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = FileCloudOutbox(rootDirectory: directory)
        let remote = RecordingCloudRemote()
        let coordinator = CloudSyncCoordinator(outbox: outbox, remote: remote)

        _ = try await coordinator.enqueue(
            CloudSyncOperation.deleteAttemptSummary(attemptID: "attempt-001"),
            mutationID: "sync-001"
        )
        // Enqueue uses the current wall clock; sync must not ask the outbox
        // for work at an earlier historical instant.
        let result = await coordinator.sync(now: Date().addingTimeInterval(1))
        #expect(result.state == .idle)
        #expect(result.pendingCount == 0)
        #expect(await remote.callCount() == 1)
        #expect(try await outbox.count() == 0)
    }

    @Test func unavailableTransportLeavesEntryLocalOnly() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = FileCloudOutbox(rootDirectory: directory)
        let coordinator = CloudSyncCoordinator(
            outbox: outbox,
            remote: FailingCloudRemote(error: .notConfigured)
        )
        _ = try await coordinator.enqueue(
            CloudSyncOperation.deleteMedia(mediaKey: "media-001"),
            mutationID: "sync-002"
        )

        let result = await coordinator.sync()
        #expect(result.state == .localOnly)
        #expect(result.pendingCount == 1)
        #expect(try await outbox.count() == 1)
    }

    @Test func offlineStateDoesNotCallRemote() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = FileCloudOutbox(rootDirectory: directory)
        let remote = RecordingCloudRemote()
        let coordinator = CloudSyncCoordinator(outbox: outbox, remote: remote)
        _ = try await coordinator.enqueue(
            CloudSyncOperation.deleteAttemptSummary(attemptID: "attempt-003"),
            mutationID: "sync-003"
        )
        await coordinator.setNetworkAvailable(false)
        let result = await coordinator.sync()
        #expect(result.state == .offline)
        #expect(result.pendingCount == 1)
        #expect(await remote.callCount() == 0)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeCloudCoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor RecordingCloudRemote: CloudRemote {
    private var calls: [(CloudSyncOperation, String)] = []

    func apply(_ operation: CloudSyncOperation, mutationID: String) async throws -> CloudMutationAck {
        calls.append((operation, mutationID))
        return CloudMutationAck(
            ok: true,
            operation: operation.kind.rawValue,
            entityId: nil,
            deduplicated: false
        )
    }

    func callCount() -> Int { calls.count }
}

private actor FailingCloudRemote: CloudRemote {
    let error: CloudSyncError

    init(error: CloudSyncError) { self.error = error }

    func apply(_ operation: CloudSyncOperation, mutationID: String) async throws -> CloudMutationAck {
        throw error
    }
}
