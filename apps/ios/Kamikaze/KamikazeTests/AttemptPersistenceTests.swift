import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct AttemptPersistenceTests {
    @MainActor
    @Test func survivesRepositoryReload() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let capture = try makeCapture(id: "reload-001", timestamp: 1)
        let first = FileAttemptRepository(rootDirectory: directory)
        try await first.save(capture)

        let reloaded = FileAttemptRepository(rootDirectory: directory)
        let loaded = try await reloaded.load(id: capture.attempt.id)
        #expect(loaded == capture)
    }

    @MainActor
    @Test func rejectsCorruptedPayload() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = try makeCapture(id: "corrupt-001", timestamp: 1)
        let repository = FileAttemptRepository(rootDirectory: directory)
        try await repository.save(capture)

        let rawURL = directory.appending(path: capture.attempt.rawSamples.relativePath)
        try Data("not motion json".utf8).write(to: rawURL, options: .atomic)

        await #expect(throws: AttemptPersistenceError.malformedPayload(capture.attempt.rawSamples.relativePath)) {
            try await repository.load(id: capture.attempt.id)
        }
    }

    @MainActor
    @Test func reportsMissingPayload() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = try makeCapture(id: "missing-001", timestamp: 1)
        let repository = FileAttemptRepository(rootDirectory: directory)
        try await repository.save(capture)
        try FileManager.default.removeItem(at: directory.appending(path: capture.attempt.rawSamples.relativePath))

        await #expect(throws: AttemptPersistenceError.missingPayload(capture.attempt.rawSamples.relativePath)) {
            try await repository.load(id: capture.attempt.id)
        }
    }

    @MainActor
    @Test func persistsOneHundredAttemptsWithoutLoss() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileAttemptRepository(rootDirectory: directory)
        for index in 0 ..< 100 {
            try await repository.save(try makeCapture(
                id: String(format: "attempt-%03d", index),
                timestamp: Double(index)
            ))
        }

        let reloaded = FileAttemptRepository(rootDirectory: directory)
        let attempts = try await reloaded.list()
        #expect(attempts.count == 100)
        #expect(Set(attempts.map(\.id)).count == 100)
        let last = try await reloaded.load(id: "attempt-099")
        #expect(last.samplePayload.samples.count == 2)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeAttemptPersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeCapture(id: String, timestamp: Double) throws -> MotionCaptureV3 {
        let samples = [
            MotionSampleV3(
                sequence: 0,
                timestampS: timestamp,
                rotationRateRadS: Vector3(x: 0, y: 0, z: 0),
                userAccelerationG: Vector3(x: 0, y: 0, z: 0),
                gravityG: Vector3(x: 0, y: 0, z: 1),
                fusedAttitude: .identity
            ),
            MotionSampleV3(
                sequence: 1,
                timestampS: timestamp + 0.01,
                rotationRateRadS: Vector3(x: 0, y: 1, z: 0),
                userAccelerationG: Vector3(x: 0.1, y: 0, z: 0),
                gravityG: Vector3(x: 0, y: 0, z: 1),
                fusedAttitude: .identity
            ),
        ]
        let payload = MotionSamplePayloadV3(attemptID: id, samples: samples)
        let rawReference = RawSampleReferenceV3(
            relativePath: "samples/\(id).json",
            encoding: .json,
            payloadSchemaVersion: MotionSchemaV3.version,
            sampleCount: samples.count,
            checksum: CapturePersistenceCodec.sha256(try CapturePersistenceCodec.encode(payload))
        )
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: String(format: "2026-08-12T00:00:%02dZ", Int(timestamp) % 60),
            captureMode: .manual,
            triggerMode: nil,
            boundaries: AttemptBoundariesV3(
                captureStartS: timestamp,
                captureEndS: timestamp + 0.01,
                motionStartS: timestamp,
                motionEndS: timestamp + 0.01,
                releaseS: nil,
                catchS: nil,
                settledS: nil
            ),
            environment: CaptureEnvironmentV3(
                device: CaptureDeviceMetadataV3(
                    modelIdentifier: "test", modelName: "Test Phone", operatingSystemName: "iOS",
                    operatingSystemVersion: "26", operatingSystemBuild: nil
                ),
                gripHand: .right,
                orientation: .portrait,
                referenceFrame: .xArbitraryZVertical,
                requestedFrequencyHz: 100,
                measuredFrequencyHz: 100
            ),
            versions: ProcessingVersionsV3(
                calibrationProfileID: nil, calibrationVersion: nil,
                detectorVersion: "test", analysisVersion: "test", scoreVersion: nil
            ),
            rawSamples: rawReference,
            importedExpoAnalysis: nil
        )
        return MotionCaptureV3(attempt: attempt, samplePayload: payload)
    }
}
