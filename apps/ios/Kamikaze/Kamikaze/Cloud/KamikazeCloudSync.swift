import Combine
import ConvexMobile
import CryptoKit
import Foundation
import Observation

nonisolated enum CloudMutationIdentity {
    static func attempt(_ summary: CloudAttemptSummaryV1) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = (try? encoder.encode(summary)) ?? Data(summary.attemptID.utf8)
        return "attempt.\(digest(Data(summary.attemptID.utf8), length: 16)).\(digest(payload, length: 32))"
    }

    static func deleteAttempt(_ attemptID: String) -> String {
        "delete-attempt.\(digest(Data(attemptID.utf8), length: 40))"
    }

    private static func digest(_ data: Data, length: Int) -> String {
        String(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined().prefix(length))
    }
}

/// Process-lifetime, metadata-only cloud coordinator. Local persistence stays
/// authoritative: this service is invoked only after a local write succeeds,
/// and every network operation first lands in the durable outbox.
@MainActor
@Observable
final class KamikazeCloudSync {
    static let shared = KamikazeCloudSync()

    private let summaryRepository: FileAttemptSummaryRepository
    private let reconciler: AttemptSummaryReconciler
    private let coordinator: CloudSyncCoordinator?
    private let remote: ConvexCloudClient?
    private let transport: ClerkConvexTransport?
    private var authTask: Task<Void, Never>?
    private var isAuthenticated = false
    private var syncInFlight = false

    private(set) var accountSnapshot: AccountSyncSnapshot

    private init(
        rootDirectory: URL = AttemptStorageLocation.applicationRoot(),
        deploymentURL: String? = KamikazeIdentityConfiguration.convexDeploymentURL
    ) {
        let attempts = FileAttemptRepository(rootDirectory: rootDirectory)
        let analyses = FileAttemptAnalysisRepository(rootDirectory: rootDirectory)
        let summaries = FileAttemptSummaryRepository(rootDirectory: rootDirectory)
        summaryRepository = summaries
        reconciler = AttemptSummaryReconciler(
            attemptRepository: attempts,
            analysisRepository: analyses,
            summaryRepository: summaries
        )
        guard let deploymentURL else {
            coordinator = nil
            remote = nil
            transport = nil
            accountSnapshot = .localOnly
            return
        }
        let connection = ConvexCloudClient.clerk(deploymentURL: deploymentURL)
        let outbox = FileCloudOutbox(rootDirectory: rootDirectory.appending(path: "CloudSync"))
        transport = connection.transport
        remote = connection.remote
        coordinator = CloudSyncCoordinator(outbox: outbox, remote: connection.remote)
        accountSnapshot = AccountSyncSnapshot(
            state: .needsAuthentication,
            detail: "Sign in to sync private attempt summaries across devices."
        )
    }

    func start() {
        guard authTask == nil, let transport else { return }
        authTask = Task { @MainActor [weak self] in
            for await state in transport.authState.values {
                guard let self else { return }
                await self.receive(state)
            }
        }
    }

    func syncNow() async {
        guard coordinator != nil, remote != nil else {
            accountSnapshot = .localOnly
            return
        }
        guard isAuthenticated else {
            accountSnapshot = AccountSyncSnapshot(
                state: .needsAuthentication,
                detail: "Finish signing in before private sync can start."
            )
            return
        }
        await synchronizeHistoricalSummaries()
    }

    func enqueue(_ summary: AttemptSummaryV1) async {
        guard let coordinator else { return }
        let cloud = CloudAttemptSummaryV1(local: summary)
        do {
            _ = try await coordinator.enqueue(
                .upsertAttemptSummary(cloud),
                mutationID: CloudMutationIdentity.attempt(cloud)
            )
            await refreshSnapshot(from: await coordinator.snapshot())
            if isAuthenticated { await drainOutbox() }
        } catch {
            accountSnapshot = AccountSyncSnapshot(
                state: .failed,
                detail: "Saved locally. Private sync will retry later."
            )
        }
    }

    func enqueueAttemptDeletion(id: String) async {
        guard let coordinator else { return }
        do {
            _ = try await coordinator.enqueue(
                .deleteAttemptSummary(attemptID: id),
                mutationID: CloudMutationIdentity.deleteAttempt(id)
            )
            if isAuthenticated { await drainOutbox() }
        } catch {
            accountSnapshot = AccountSyncSnapshot(
                state: .failed,
                detail: "Deleted locally. Cloud deletion will retry later."
            )
        }
    }

    private func receive(_ state: AuthState<String>) async {
        switch state {
        case .loading:
            accountSnapshot = AccountSyncSnapshot(
                state: .syncing,
                detail: "Connecting your private account…"
            )
        case .unauthenticated:
            isAuthenticated = false
            accountSnapshot = AccountSyncSnapshot(
                state: .needsAuthentication,
                detail: "Sign in to sync private attempt summaries across devices."
            )
        case .authenticated:
            isAuthenticated = true
            await synchronizeHistoricalSummaries()
        }
    }

    private func synchronizeHistoricalSummaries() async {
        guard !syncInFlight, let coordinator, let remote else { return }
        syncInFlight = true
        defer { syncInFlight = false }
        accountSnapshot = AccountSyncSnapshot(
            state: .syncing,
            detail: "Preparing your local history for private sync…"
        )
        do {
            _ = try await remote.ensureCurrentUser()
            _ = try await reconciler.reconcile()
            let summaries = try await summaryRepository.all()
            for summary in summaries {
                let cloud = CloudAttemptSummaryV1(local: summary)
                _ = try await coordinator.enqueue(
                    .upsertAttemptSummary(cloud),
                    mutationID: CloudMutationIdentity.attempt(cloud)
                )
            }
            await drainOutbox(totalSummaryCount: summaries.count)
        } catch {
            accountSnapshot = AccountSyncSnapshot(
                state: .failed,
                detail: "Your history is safe locally. Sync could not connect yet."
            )
        }
    }

    private func drainOutbox(totalSummaryCount: Int? = nil) async {
        guard let coordinator else { return }
        var previousPending = Int.max
        for _ in 0 ..< 100 {
            let snapshot = await coordinator.sync(batchSize: 50)
            await refreshSnapshot(from: snapshot, totalSummaryCount: totalSummaryCount)
            guard snapshot.pendingCount > 0 else { return }
            guard snapshot.pendingCount < previousPending else { return }
            previousPending = snapshot.pendingCount
        }
    }

    private func refreshSnapshot(
        from snapshot: CloudSyncSnapshot,
        totalSummaryCount: Int? = nil
    ) async {
        switch snapshot.state {
        case .localOnly:
            accountSnapshot = .localOnly
        case .offline:
            accountSnapshot = AccountSyncSnapshot(
                state: .unavailable,
                detail: "Offline. \(snapshot.pendingCount) change(s) are queued safely."
            )
        case .syncing:
            accountSnapshot = AccountSyncSnapshot(
                state: .syncing,
                detail: "Syncing \(snapshot.pendingCount) private change(s)…"
            )
        case .needsAuthentication:
            accountSnapshot = AccountSyncSnapshot(
                state: .needsAuthentication,
                detail: "Your Clerk session needs to be refreshed."
            )
        case .failed:
            accountSnapshot = AccountSyncSnapshot(
                state: .failed,
                detail: "Saved locally. \(snapshot.pendingCount) change(s) will retry."
            )
        case .idle:
            let count = totalSummaryCount.map { "\($0) historical attempt(s) synced. " } ?? ""
            accountSnapshot = AccountSyncSnapshot(
                state: .ready,
                detail: "\(count)New attempts sync automatically; raw sensor and camera files stay on this iPhone.",
                lastSyncedAt: snapshot.lastSyncedAt
            )
        }
    }
}
