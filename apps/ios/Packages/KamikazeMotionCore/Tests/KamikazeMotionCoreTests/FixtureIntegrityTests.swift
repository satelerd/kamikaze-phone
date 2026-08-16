import CryptoKit
import Foundation
import Testing
@testable import KamikazeMotionCore

@Suite("Verified motion fixture manifest")
struct FixtureIntegrityTests {
    @Test("v3 manifest verifies immutable Expo v2 seed fixtures")
    func verifiesExpoSeedFixtures() throws {
        let manifest = try loadManifest()

        #expect(manifest.format == "kpf-motion-fixture-manifest")
        #expect(manifest.manifestSchemaVersion == 1)
        #expect(manifest.datasetSchemaVersion == 3)
        #expect(manifest.vocabularyVersion == 1)
        #expect(manifest.fixtures.count == 2)
        #expect(Set(manifest.fixtures.map(\.id)).count == manifest.fixtures.count)
        #expect(Set(manifest.fixtures.map(\.file)).count == manifest.fixtures.count)
        #expect(Set(manifest.fixtures.map(\.sha256)).count == manifest.fixtures.count)

        for fixture in manifest.fixtures {
            try verifyManifestEntry(fixture)
        }
    }

    private func verifyManifestEntry(_ fixture: FixtureManifest.Fixture) throws {
        #expect(fixture.id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil)
        #expect(fixture.kind == "labelled-attempt")
        #expect(fixture.use == ["migration", "replay", "classification"])
        #expect(fixture.split == "seed")
        #expect(fixture.expected.outcome == "recognized")
        #expect(!fixture.expected.trickID.isEmpty)
        #expect(!fixture.expected.displayName.isEmpty)
        #expect(fixture.provenance.runtime == "expo")
        #expect(fixture.provenance.gripHand == "right")
        #expect(fixture.provenance.screenOrientation == "portrait")
        #expect(fixture.provenance.metadataConfidence == "user-confirmed-outside-payload")
        #expect(fixture.capture.mode == "manual")
        #expect(fixture.capture.requestedHz == 100)
        #expect(fixture.capture.caseState == "unknown")
        #expect(fixture.payload.format == "kpf-labelled-capture-v1")
        #expect(fixture.payload.attemptSchemaVersion == 2)
        #expect(fixture.file.hasPrefix("fixtures/motion/v2/labelled/"))
        #expect(!fixture.file.hasPrefix("/"))
        #expect(!fixture.file.split(separator: "/").contains(".."))
        #expect(fixture.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)

        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(fixture.file))
        #expect(sha256(data) == fixture.sha256)

        let capture = try JSONDecoder().decode(ExpoLabelledCaptureV1.self, from: data)
        #expect(capture.schema == fixture.payload.format)
        #expect(capture.expectedTrick == fixture.expected.displayName)
        #expect(capture.recordedAttempt.schemaVersion == fixture.payload.attemptSchemaVersion)
        #expect(capture.recordedAttempt.source == .sensor)
        #expect(capture.recordedAttempt.captureMode == .manual)
        #expect(capture.recordedAttempt.samples.count == fixture.payload.sampleCount)
        #expect(capture.recordedAttempt.sampleCount == fixture.payload.sampleCount)

        let samples = capture.recordedAttempt.samples
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy(hasFiniteValues))
        #expect(zip(samples, samples.dropFirst()).allSatisfy { previous, next in
            next.timestampS > previous.timestampS
        })
    }

    private var manifestURL: URL {
        repositoryRoot.appendingPathComponent("fixtures/motion/v3/manifest.json")
    }

    private var repositoryRoot: URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func loadManifest() throws -> FixtureManifest {
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(FixtureManifest.self, from: data)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func hasFiniteValues(_ sample: MotionSample) -> Bool {
        [
            sample.timestampS,
            sample.accelerationIncludingGravity.x,
            sample.accelerationIncludingGravity.y,
            sample.accelerationIncludingGravity.z,
            sample.rotationRateDps.x,
            sample.rotationRateDps.y,
            sample.rotationRateDps.z,
        ].allSatisfy(\.isFinite)
    }
}

private struct FixtureManifest: Decodable {
    let format: String
    let manifestSchemaVersion: Int
    let datasetSchemaVersion: Int
    let vocabularyVersion: Int
    let fixtures: [Fixture]

    struct Fixture: Decodable {
        let id: String
        let file: String
        let sha256: String
        let payload: Payload
        let kind: String
        let use: [String]
        let split: String
        let expected: Expected
        let provenance: Provenance
        let capture: Capture
    }

    struct Payload: Decodable {
        let format: String
        let attemptSchemaVersion: Int
        let sampleCount: Int
    }

    struct Expected: Decodable {
        let trickID: String
        let displayName: String
        let outcome: String

        enum CodingKeys: String, CodingKey {
            case trickID = "trickId"
            case displayName
            case outcome
        }
    }

    struct Provenance: Decodable {
        let runtime: String
        let deviceModel: String
        let osVersion: String
        let gripHand: String
        let screenOrientation: String
        let metadataConfidence: String
    }

    struct Capture: Decodable {
        let mode: String
        let requestedHz: Int
        let caseState: String
    }
}
