import Foundation

nonisolated struct CloudOutboxEntry: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let mutationID: String
    let operation: CloudSyncOperation
    let enqueuedAt: Date
    var attemptCount: Int
    var nextAttemptAt: Date
    var lastError: String?

    init(
        mutationID: String,
        operation: CloudSyncOperation,
        enqueuedAt: Date = Date(),
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = mutationID
        self.mutationID = mutationID
        self.operation = operation
        self.enqueuedAt = enqueuedAt
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt ?? enqueuedAt
        self.lastError = lastError
    }
}

nonisolated struct CloudRetryPolicy: Equatable, Sendable {
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval

    nonisolated static let `default` = Self(baseDelay: 2, maximumDelay: 60 * 60)

    func delay(after attemptCount: Int) -> TimeInterval {
        let exponent = max(0, min(attemptCount - 1, 10))
        return min(maximumDelay, baseDelay * pow(2, Double(exponent)))
    }
}

nonisolated enum CloudOutboxError: Error, Equatable, Sendable {
    case invalidMutationID
    case mutationIDCollision
    case ioFailure
}

/// File-backed, metadata-only outbox. It is independent from the existing
/// AttemptRepository so a sync failure can never block or mutate local play.
actor FileCloudOutbox {
    private struct FileV1: Codable {
        let schemaVersion: Int
        let entries: [CloudOutboxEntry]
    }

    static let schemaVersion = 1

    private let rootDirectory: URL
    private let indexURL: URL
    private var loaded = false
    private var entries: [CloudOutboxEntry] = []

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.indexURL = rootDirectory.standardizedFileURL.appending(path: "cloud-outbox.v1.json")
    }

    @discardableResult
    func enqueue(
        _ operation: CloudSyncOperation,
        mutationID: String = UUID().uuidString,
        enqueuedAt: Date = Date()
    ) throws -> CloudOutboxEntry {
        try loadIfNeeded()
        guard Self.isValidMutationID(mutationID) else {
            throw CloudOutboxError.invalidMutationID
        }
        if let existing = entries.first(where: { $0.mutationID == mutationID }) {
            guard existing.operation == operation else { throw CloudOutboxError.mutationIDCollision }
            return existing
        }
        let entry = CloudOutboxEntry(
            mutationID: mutationID,
            operation: operation,
            enqueuedAt: enqueuedAt
        )
        entries.append(entry)
        try persist()
        return entry
    }

    func all() throws -> [CloudOutboxEntry] {
        try loadIfNeeded()
        return entries.sorted { $0.enqueuedAt == $1.enqueuedAt ? $0.id < $1.id : $0.enqueuedAt < $1.enqueuedAt }
    }

    func ready(now: Date = Date(), limit: Int = 20) throws -> [CloudOutboxEntry] {
        let boundedLimit = max(1, min(100, limit))
        return try all()
            .filter { $0.nextAttemptAt <= now }
            .prefix(boundedLimit)
            .map { $0 }
    }

    func count() throws -> Int {
        try loadIfNeeded()
        return entries.count
    }

    func remove(mutationID: String) throws {
        try loadIfNeeded()
        let oldCount = entries.count
        entries.removeAll { $0.mutationID == mutationID }
        if entries.count != oldCount { try persist() }
    }

    @discardableResult
    func markFailure(
        mutationID: String,
        error: String,
        now: Date = Date(),
        policy: CloudRetryPolicy = .default
    ) throws -> CloudOutboxEntry? {
        try loadIfNeeded()
        guard let index = entries.firstIndex(where: { $0.mutationID == mutationID }) else { return nil }
        var entry = entries[index]
        entry.attemptCount += 1
        entry.lastError = String(error.prefix(500))
        entry.nextAttemptAt = now.addingTimeInterval(policy.delay(after: entry.attemptCount))
        entries[index] = entry
        try persist()
        return entry
    }

    func clear() throws {
        try loadIfNeeded()
        guard !entries.isEmpty else { return }
        entries.removeAll()
        try persist()
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexURL)
            let file = try JSONDecoder().decode(FileV1.self, from: data)
            guard file.schemaVersion == Self.schemaVersion else { return }
            entries = file.entries
        } catch {
            throw CloudOutboxError.ioFailure
        }
    }

    private func persist() throws {
        do {
            try FileManager.default.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true
            )
            let file = FileV1(schemaVersion: Self.schemaVersion, entries: entries)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).write(to: indexURL, options: .atomic)
        } catch {
            throw CloudOutboxError.ioFailure
        }
    }

    private static func isValidMutationID(_ value: String) -> Bool {
        guard (1 ... 160).contains(value.count) else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || ".:_-".contains($0) }
    }
}
