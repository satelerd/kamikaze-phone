import Foundation
import KamikazeMotionCore

nonisolated enum AttemptStorageLocation {
    static func applicationRoot() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return support.appending(path: "Kamikaze/Attempts")
    }
}

/// Versioned interpretation stored separately from immutable sensor evidence.
/// Future matchers can add another revision without rewriting the raw capture.
nonisolated struct AttemptAnalysisRecord: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let attemptID: String
    let analyzedAtISO8601: String
    let result: TrickMatchResult

    init(attemptID: String, result: TrickMatchResult, analyzedAt: Date = Date()) {
        self.schemaVersion = Self.schemaVersion
        self.attemptID = attemptID
        self.analyzedAtISO8601 = ISO8601DateFormatter().string(from: analyzedAt)
        self.result = result
    }
}

protocol AttemptAnalysisRepository: Sendable {
    func save(_ record: AttemptAnalysisRecord) async throws
    func load(attemptID: String) async throws -> AttemptAnalysisRecord?
}

actor FileAttemptAnalysisRepository: AttemptAnalysisRepository {
    private let directory: URL

    init(rootDirectory: URL) {
        directory = rootDirectory.appending(path: "analysis")
    }

    func save(_ record: AttemptAnalysisRecord) throws {
        guard record.schemaVersion == AttemptAnalysisRecord.schemaVersion,
              isSafeID(record.attemptID) else {
            throw AttemptPersistenceError.invalidCapture("Invalid analysis record.")
        }
        let data = try CapturePersistenceCodec.encode(record)
        try AtomicFileWriter.write(data, to: url(for: record.attemptID))
    }

    func load(attemptID: String) throws -> AttemptAnalysisRecord? {
        guard isSafeID(attemptID) else {
            throw AttemptPersistenceError.invalidCapture("Invalid attempt identifier.")
        }
        let target = url(for: attemptID)
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        let data = try Data(contentsOf: target)
        let record = try CapturePersistenceCodec.decode(AttemptAnalysisRecord.self, from: data)
        guard record.schemaVersion == AttemptAnalysisRecord.schemaVersion,
              record.attemptID == attemptID else {
            throw AttemptPersistenceError.invalidCapture("Analysis record does not match its attempt.")
        }
        return record
    }

    private func url(for attemptID: String) -> URL {
        directory.appending(path: "\(attemptID).analysis-v1.json")
    }

    private func isSafeID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
