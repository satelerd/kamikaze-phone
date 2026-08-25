import Foundation

nonisolated protocol CommunityTrickRepository: Sendable {
    func load() async throws -> CommunityTrickSnapshot
    func save(_ snapshot: CommunityTrickSnapshot) async throws
}

actor FileCommunityTrickRepository: CommunityTrickRepository {
    enum RepositoryError: LocalizedError, Equatable {
        case invalidSnapshot

        var errorDescription: String? {
            switch self {
            case .invalidSnapshot: "Community trick data is invalid or inconsistent."
            }
        }
    }

    private let fileURL: URL

    init(rootDirectory: URL = CommunityTrickStorageLocation.applicationRoot()) {
        fileURL = rootDirectory
            .appending(path: "community-tricks")
            .appending(path: "community-tricks-v1.json")
    }

    func load() throws -> CommunityTrickSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let snapshot = try CapturePersistenceCodec.decode(
            CommunityTrickSnapshot.self,
            from: Data(contentsOf: fileURL)
        )
        guard Self.isValid(snapshot) else { throw RepositoryError.invalidSnapshot }
        return snapshot
    }

    func save(_ snapshot: CommunityTrickSnapshot) throws {
        guard Self.isValid(snapshot) else { throw RepositoryError.invalidSnapshot }
        let data = try CapturePersistenceCodec.encode(snapshot)
        let decoded = try CapturePersistenceCodec.decode(CommunityTrickSnapshot.self, from: data)
        guard decoded == snapshot else { throw RepositoryError.invalidSnapshot }
        try AtomicFileWriter.write(data, to: fileURL)
    }

    private static func isValid(_ snapshot: CommunityTrickSnapshot) -> Bool {
        guard snapshot.schemaVersion == CommunityTrickSnapshot.schemaVersion,
              snapshot.proposals.allSatisfy(\.isValidDraft),
              snapshot.examples.allSatisfy(\.isValid) else { return false }

        let proposalIDs = snapshot.proposals.map(\.id)
        let exampleIDs = snapshot.examples.map(\.id)
        guard Set(proposalIDs).count == proposalIDs.count,
              Set(exampleIDs).count == exampleIDs.count else { return false }
        let proposalIDSet = Set(proposalIDs)
        let exampleIDSet = Set(exampleIDs)
        guard snapshot.examples.allSatisfy({ proposalIDSet.contains($0.proposalID) }),
              snapshot.proposalReviews.allSatisfy({ proposalIDSet.contains($0.proposalID) }),
              snapshot.exampleReviews.allSatisfy({
                  proposalIDSet.contains($0.proposalID) && exampleIDSet.contains($0.exampleID)
              }),
              snapshot.trainingEvidence.allSatisfy({
                  proposalIDSet.contains($0.proposalID) && exampleIDSet.contains($0.exampleID)
              }) else { return false }

        let promotedExampleIDs = snapshot.trainingEvidence.map(\.exampleID)
        return Set(promotedExampleIDs).count == promotedExampleIDs.count
    }
}

nonisolated enum CommunityTrickStorageLocation {
    static func applicationRoot() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return support.appending(path: "Kamikaze")
    }
}

actor MemoryCommunityTrickRepository: CommunityTrickRepository {
    private var snapshot: CommunityTrickSnapshot

    init(snapshot: CommunityTrickSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func load() -> CommunityTrickSnapshot { snapshot }
    func save(_ snapshot: CommunityTrickSnapshot) { self.snapshot = snapshot }
}
