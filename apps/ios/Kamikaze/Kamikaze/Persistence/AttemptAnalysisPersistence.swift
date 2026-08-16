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
nonisolated enum HumanAttemptOutcome: String, Codable, CaseIterable, Equatable, Sendable {
    case landed
    case missed
    case unclear
    case noAttempt

    var displayName: String {
        switch self {
        case .landed: "LANDED"
        case .missed: "MISSED"
        case .unclear: "UNCLEAR"
        case .noAttempt: "NO ATTEMPT"
        }
    }
}

/// Player-provided ground truth. This is deliberately stored beside, never
/// inside, the machine result so re-analysis cannot erase human evidence.
nonisolated struct HumanAttemptReview: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let reviewedAtISO8601: String
    let trickID: BuiltInTrickID?
    let outcome: HumanAttemptOutcome
    let notes: String

    init(
        trickID: BuiltInTrickID?,
        outcome: HumanAttemptOutcome,
        notes: String = "",
        reviewedAt: Date = Date()
    ) {
        self.schemaVersion = Self.schemaVersion
        self.reviewedAtISO8601 = ISO8601DateFormatter().string(from: reviewedAt)
        self.trickID = outcome == .noAttempt ? nil : trickID
        self.outcome = outcome
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        schemaVersion == Self.schemaVersion
            && (outcome == .noAttempt ? trickID == nil : trickID != nil)
    }
}

nonisolated struct AttemptAnalysisRecord: Codable, Equatable, Sendable {
    static let schemaVersion = 2

    let schemaVersion: Int
    let attemptID: String
    let analyzedAtISO8601: String
    let result: TrickMatchResult
    let humanReview: HumanAttemptReview?

    init(
        attemptID: String,
        result: TrickMatchResult,
        humanReview: HumanAttemptReview? = nil,
        analyzedAt: Date = Date()
    ) {
        self.schemaVersion = Self.schemaVersion
        self.attemptID = attemptID
        self.analyzedAtISO8601 = ISO8601DateFormatter().string(from: analyzedAt)
        self.result = result
        self.humanReview = humanReview
    }

}

protocol AttemptAnalysisRepository: Sendable {
    func save(_ record: AttemptAnalysisRecord) async throws
    func load(attemptID: String) async throws -> AttemptAnalysisRecord?
    func delete(attemptID: String) async throws
}

actor FileAttemptAnalysisRepository: AttemptAnalysisRepository {
    private let directory: URL

    init(rootDirectory: URL) {
        directory = rootDirectory.appending(path: "analysis")
    }

    func save(_ record: AttemptAnalysisRecord) throws {
        guard record.schemaVersion == AttemptAnalysisRecord.schemaVersion,
              record.humanReview?.isValid != false,
              isSafeID(record.attemptID) else {
            throw AttemptPersistenceError.invalidCapture("Invalid analysis record.")
        }
        // A matcher refresh with no review must never overwrite human evidence.
        let existingReview = try load(attemptID: record.attemptID)?.humanReview
        let merged = existingReview != nil && record.humanReview == nil
            ? AttemptAnalysisRecord(
                attemptID: record.attemptID,
                result: record.result,
                humanReview: existingReview
            )
            : record
        let data = try CapturePersistenceCodec.encode(merged)
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
        guard (1 ... AttemptAnalysisRecord.schemaVersion).contains(record.schemaVersion),
              record.humanReview?.isValid != false,
              record.attemptID == attemptID else {
            throw AttemptPersistenceError.invalidCapture("Analysis record does not match its attempt.")
        }
        return record
    }

    func delete(attemptID: String) throws {
        guard isSafeID(attemptID) else {
            throw AttemptPersistenceError.invalidCapture("Invalid attempt identifier.")
        }
        let target = url(for: attemptID)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            throw AttemptPersistenceError.ioFailure
        }
    }

    private func url(for attemptID: String) -> URL {
        directory.appending(path: "\(attemptID).analysis-v1.json")
    }

    private func isSafeID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
