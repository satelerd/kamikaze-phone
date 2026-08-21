import Foundation

nonisolated enum CloudSyncState: Equatable, Sendable {
    case localOnly
    case offline
    case idle
    case syncing
    case needsAuthentication
    case failed
}

nonisolated struct CloudSyncSnapshot: Equatable, Sendable {
    let state: CloudSyncState
    let pendingCount: Int
    let lastSyncedAt: Date?
    let lastError: String?
}

/// Coordinates bounded foreground sync. It never deletes outbox entries on a
/// transient error and never asks the remote for raw motion evidence.
actor CloudSyncCoordinator {
    private let outbox: FileCloudOutbox
    private let remote: any CloudRemote
    private let retryPolicy: CloudRetryPolicy
    private var networkAvailable = true
    private var snapshotValue = CloudSyncSnapshot(
        state: .localOnly,
        pendingCount: 0,
        lastSyncedAt: nil,
        lastError: nil
    )

    init(
        outbox: FileCloudOutbox,
        remote: any CloudRemote,
        retryPolicy: CloudRetryPolicy = .default
    ) {
        self.outbox = outbox
        self.remote = remote
        self.retryPolicy = retryPolicy
    }

    func snapshot() -> CloudSyncSnapshot {
        snapshotValue
    }

    func setNetworkAvailable(_ available: Bool) async {
        networkAvailable = available
        if !available {
            await refresh(state: .offline, error: nil)
        } else if snapshotValue.state == .offline {
            await refresh(state: .idle, error: nil)
        }
    }

    @discardableResult
    func enqueue(_ operation: CloudSyncOperation, mutationID: String = UUID().uuidString) async throws -> String {
        let entry = try await outbox.enqueue(operation, mutationID: mutationID)
        let pending = (try? await outbox.count()) ?? 1
        if snapshotValue.state == .localOnly {
            await refresh(state: .idle, pending: pending, error: nil)
        } else {
            await refresh(state: snapshotValue.state, pending: pending, error: snapshotValue.lastError)
        }
        return entry.mutationID
    }

    @discardableResult
    func sync(now: Date = Date(), batchSize: Int = 20) async -> CloudSyncSnapshot {
        guard networkAvailable else {
            await refresh(state: .offline, error: nil)
            return snapshotValue
        }
        await refresh(state: .syncing, error: nil)
        let pending: [CloudOutboxEntry]
        do {
            pending = try await outbox.ready(now: now, limit: batchSize)
        } catch {
            await refresh(state: .failed, error: String(describing: error))
            return snapshotValue
        }
        if pending.isEmpty {
            let count = (try? await outbox.count()) ?? 0
            await refresh(state: .idle, pending: count, syncedAt: snapshotValue.lastSyncedAt, error: nil)
            return snapshotValue
        }

        var lastError: String?
        var authFailure = false
        var localOnly = false
        var didSync = false
        for entry in pending {
            do {
                _ = try await remote.apply(entry.operation, mutationID: entry.mutationID)
                try await outbox.remove(mutationID: entry.mutationID)
                didSync = true
            } catch let error as CloudSyncError {
                lastError = String(describing: error)
                switch error {
                case .notConfigured:
                    localOnly = true
                case .unauthenticated:
                    authFailure = true
                default:
                    _ = try? await outbox.markFailure(
                        mutationID: entry.mutationID,
                        error: lastError ?? "sync failed",
                        now: now,
                        policy: retryPolicy
                    )
                }
                break
            } catch {
                lastError = String(describing: error)
                _ = try? await outbox.markFailure(
                    mutationID: entry.mutationID,
                    error: lastError ?? "sync failed",
                    now: now,
                    policy: retryPolicy
                )
                break
            }
        }

        let count = (try? await outbox.count()) ?? pending.count
        let state: CloudSyncState
        if localOnly {
            state = .localOnly
        } else if authFailure {
            state = .needsAuthentication
        } else if lastError != nil {
            state = .failed
        } else {
            state = .idle
        }
        await refresh(
            state: state,
            pending: count,
            syncedAt: didSync ? now : snapshotValue.lastSyncedAt,
            error: lastError
        )
        return snapshotValue
    }

    private func refresh(
        state: CloudSyncState,
        pending: Int? = nil,
        syncedAt: Date? = nil,
        error: String?
    ) async {
        let count: Int
        if let pending {
            count = pending
        } else {
            count = (try? await outbox.count()) ?? snapshotValue.pendingCount
        }
        snapshotValue = CloudSyncSnapshot(
            state: state,
            pendingCount: count,
            lastSyncedAt: syncedAt ?? snapshotValue.lastSyncedAt,
            lastError: error
        )
    }
}
