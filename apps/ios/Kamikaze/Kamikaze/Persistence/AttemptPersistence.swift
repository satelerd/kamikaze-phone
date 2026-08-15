import CryptoKit
import Foundation
import KamikazeMotionCore

/// File-backed persistence boundary for the first native beta. The protocol is
/// intentionally small so SwiftData can replace the metadata index later
/// without changing capture or replay clients.
protocol SampleStore: Sendable {
    func store(
        _ payload: MotionSamplePayloadV3,
        at reference: RawSampleReferenceV3
    ) async throws

    func load(reference: RawSampleReferenceV3) async throws -> MotionSamplePayloadV3

    func remove(reference: RawSampleReferenceV3) async throws
}

protocol AttemptRepository: Sendable {
    func save(_ capture: MotionCaptureV3) async throws
    func load(id: String) async throws -> MotionCaptureV3
    func list() async throws -> [MotionAttemptV3]
    /// Permanently removes the attempt's metadata and raw payload. Deleting a
    /// missing attempt is a no-op, so the transaction is safely retryable.
    func delete(id: String) async throws
}

nonisolated enum AttemptPersistenceError: Error, Equatable, Sendable {
    case invalidRawReference
    case invalidCapture(String)
    case missingMetadata(String)
    case missingPayload(String)
    case malformedMetadataIndex
    case malformedPayload(String)
    case payloadAttemptIDMismatch(expected: String, actual: String)
    case sampleCountMismatch(expected: Int, actual: Int)
    case payloadSchemaMismatch(expected: Int, actual: Int)
    case checksumMismatch
    case ioFailure
}

/// Canonical JSON is kept at this boundary: changing encoder formatting would
/// change the evidence checksum, so it is never a presentation concern.
nonisolated enum CapturePersistenceCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

actor FileSampleStore: SampleStore {
    private let rootDirectory: URL

    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory.standardizedFileURL
    }

    func store(
        _ payload: MotionSamplePayloadV3,
        at reference: RawSampleReferenceV3
    ) throws {
        try validate(payload, against: reference)
        let target = try url(for: reference.relativePath)
        let data = try CapturePersistenceCodec.encode(payload)
        try AtomicFileWriter.write(data, to: target)
    }

    func remove(reference: RawSampleReferenceV3) throws {
        let target = try url(for: reference.relativePath)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            throw AttemptPersistenceError.ioFailure
        }
    }

    func load(reference: RawSampleReferenceV3) throws -> MotionSamplePayloadV3 {
        let target = try url(for: reference.relativePath)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw AttemptPersistenceError.missingPayload(reference.relativePath)
        }
        let data: Data
        do {
            data = try Data(contentsOf: target)
        } catch {
            throw AttemptPersistenceError.ioFailure
        }
        let payload: MotionSamplePayloadV3
        do {
            payload = try CapturePersistenceCodec.decode(MotionSamplePayloadV3.self, from: data)
        } catch {
            throw AttemptPersistenceError.malformedPayload(reference.relativePath)
        }
        try validate(payload, against: reference, encodedData: data)
        return payload
    }

    private func validate(
        _ payload: MotionSamplePayloadV3,
        against reference: RawSampleReferenceV3,
        encodedData: Data? = nil
    ) throws {
        guard payload.schemaVersion == reference.payloadSchemaVersion else {
            throw AttemptPersistenceError.payloadSchemaMismatch(
                expected: reference.payloadSchemaVersion,
                actual: payload.schemaVersion
            )
        }
        guard payload.samples.count == reference.sampleCount else {
            throw AttemptPersistenceError.sampleCountMismatch(
                expected: reference.sampleCount,
                actual: payload.samples.count
            )
        }
        let data: Data
        if let encodedData {
            data = encodedData
        } else {
            data = try CapturePersistenceCodec.encode(payload)
        }
        guard CapturePersistenceCodec.sha256(data) == reference.checksum else {
            throw AttemptPersistenceError.checksumMismatch
        }
    }

    private func url(for relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw AttemptPersistenceError.invalidRawReference
        }
        let candidate = rootDirectory.appending(path: relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(rootDirectory.path + "/") else {
            throw AttemptPersistenceError.invalidRawReference
        }
        return candidate
    }
}

actor FileAttemptRepository: AttemptRepository {
    private let rootDirectory: URL
    private let indexURL: URL
    private let sampleStore: any SampleStore

    init(
        rootDirectory: URL,
        sampleStore: (any SampleStore)? = nil
    ) {
        let root = rootDirectory.standardizedFileURL
        self.rootDirectory = root
        self.indexURL = root.appending(path: "attempt-index.v3.json")
        self.sampleStore = sampleStore ?? FileSampleStore(rootDirectory: root)
    }

    func save(_ capture: MotionCaptureV3) async throws {
        let attempt = capture.attempt
        guard attempt.schemaVersion == MotionSchemaV3.version else {
            throw AttemptPersistenceError.invalidCapture("Unsupported attempt schema.")
        }
        guard attempt.id == capture.samplePayload.attemptID else {
            throw AttemptPersistenceError.payloadAttemptIDMismatch(
                expected: attempt.id,
                actual: capture.samplePayload.attemptID
            )
        }
        try await sampleStore.store(capture.samplePayload, at: attempt.rawSamples)

        var entries = try readIndex()
        entries.removeAll { $0.id == attempt.id }
        entries.append(attempt)
        entries.sort { $0.id < $1.id }
        try writeIndex(entries)
    }

    func load(id: String) async throws -> MotionCaptureV3 {
        guard let attempt = try readIndex().first(where: { $0.id == id }) else {
            throw AttemptPersistenceError.missingMetadata(id)
        }
        let payload = try await sampleStore.load(reference: attempt.rawSamples)
        guard payload.attemptID == attempt.id else {
            throw AttemptPersistenceError.payloadAttemptIDMismatch(
                expected: attempt.id,
                actual: payload.attemptID
            )
        }
        return MotionCaptureV3(attempt: attempt, samplePayload: payload)
    }

    func list() throws -> [MotionAttemptV3] {
        try readIndex().sorted {
            if $0.recordedAtISO8601 == $1.recordedAtISO8601 { return $0.id > $1.id }
            return $0.recordedAtISO8601 > $1.recordedAtISO8601
        }
    }

    func delete(id: String) async throws {
        var entries = try readIndex()
        guard let attempt = entries.first(where: { $0.id == id }) else { return }
        // Index first: once the metadata entry is gone the attempt no longer
        // exists to any reader, and an interrupted payload removal only leaves
        // an unreachable file behind.
        entries.removeAll { $0.id == id }
        try writeIndex(entries)
        try await sampleStore.remove(reference: attempt.rawSamples)
    }

    private func readIndex() throws -> [MotionAttemptV3] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: indexURL)
        } catch {
            throw AttemptPersistenceError.ioFailure
        }
        do {
            return try CapturePersistenceCodec.decode([MotionAttemptV3].self, from: data)
        } catch {
            throw AttemptPersistenceError.malformedMetadataIndex
        }
    }

    private func writeIndex(_ entries: [MotionAttemptV3]) throws {
        let data = try CapturePersistenceCodec.encode(entries)
        try AtomicFileWriter.write(data, to: indexURL)
    }
}

nonisolated enum AtomicFileWriter {
    static func write(_ data: Data, to destination: URL) throws {
        let directory = destination.deletingLastPathComponent()
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
            try data.write(to: temporary, options: .withoutOverwriting)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch let error as AttemptPersistenceError {
            throw error
        } catch {
            throw AttemptPersistenceError.ioFailure
        }
    }
}
