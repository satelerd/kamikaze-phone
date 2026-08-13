import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct DebugMotionCaptureExportTests {
    @Test func exportedCaptureIsSelfContainedAndVerifiable() throws {
        let export = try makeExport(checksum: nil)
        let data = try DebugMotionCaptureStore.encodedJSON(export)
        let validated = try DebugMotionCaptureStore.validateExport(data)

        #expect(validated.capture == export.capture)
        #expect(validated.label.expectedTrickID == .flip)
        #expect(validated.boundarySemantics == "manual-ui-markers-v1")
        #expect(validated.diagnostics.timestampGapCount == 0)
        #expect(validated.diagnostics.sequenceGapCount == 0)
    }

    @Test func legacyFrontAndBackLabelsDecodeIntoCorrectedNames() throws {
        let legacyFront = try JSONDecoder().decode(DebugTrickID.self, from: Data("\"front-flip\"".utf8))
        let legacyBack = try JSONDecoder().decode(DebugTrickID.self, from: Data("\"back-flip\"".utf8))
        #expect(legacyFront == .flip)
        #expect(legacyBack == .reverseFlip)
    }

    @Test func datasetExportIncludesOnlyHumanClassifiedOutcomes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeLabelledDatasetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let inputs: [(String, DebugMotionCaptureOutcome)] = [
            ("landed-001", .landed),
            ("missed-001", .missed),
            ("unclear-001", .unclear),
        ]
        for (id, outcome) in inputs {
            let export = try makeExport(checksum: nil, id: id, outcome: outcome)
            try DebugMotionCaptureStore.encodedJSON(export).write(
                to: directory.appending(path: "\(id).kamikaze-motion-v3.json"),
                options: .atomic
            )
        }

        let generated = try DebugMotionCaptureStore.exportClassifiedDataset(from: directory)
        let saved = try #require(generated)
        #expect(saved.captureCount == 2)
        let dataset = try JSONDecoder().decode(
            DebugMotionDatasetExportV1.self,
            from: Data(contentsOf: saved.exportURL)
        )
        #expect(dataset.captures.map(\.label.outcome) == [.landed, .missed])
    }

    @Test func rejectsExportWhoseEmbeddedPayloadDoesNotMatchChecksum() throws {
        let export = try makeExport(checksum: String(repeating: "0", count: 64))
        let data = try DebugMotionCaptureStore.encodedJSON(export)

        #expect(throws: DebugMotionCaptureStore.ValidationError.checksumMismatch) {
            try DebugMotionCaptureStore.validateExport(data)
        }
    }

    private func makeExport(
        checksum suppliedChecksum: String?,
        id: String = "pilot-flip-001",
        outcome: DebugMotionCaptureOutcome = .landed
    ) throws -> DebugMotionCaptureExportV1 {
        let samples = [
            sample(sequence: 41, timestampS: 10, angle: 0),
            sample(sequence: 42, timestampS: 10.01, angle: 0.3),
            sample(sequence: 43, timestampS: 10.02, angle: 0.6),
        ]
        let payload = MotionSamplePayloadV3(attemptID: id, samples: samples)
        let checksum = try suppliedChecksum
            ?? DebugMotionCaptureStore.sha256(DebugMotionCaptureStore.encodedJSON(payload))
        let reference = RawSampleReferenceV3(
            relativePath: "\(id).samples.v3.json",
            encoding: .json,
            payloadSchemaVersion: MotionSchemaV3.version,
            sampleCount: samples.count,
            checksum: checksum
        )
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: "2026-08-12T20:00:00Z",
            captureMode: .manual,
            triggerMode: nil,
            boundaries: AttemptBoundariesV3(
                captureStartS: 10,
                captureEndS: 10.02,
                motionStartS: 10.005,
                motionEndS: 10.015,
                releaseS: nil,
                catchS: nil,
                settledS: nil
            ),
            environment: CaptureEnvironmentV3(
                device: CaptureDeviceMetadataV3(
                    modelIdentifier: "iPhone15,5",
                    modelName: "iPhone",
                    operatingSystemName: "iOS",
                    operatingSystemVersion: "26.5",
                    operatingSystemBuild: "23F81"
                ),
                gripHand: .right,
                orientation: .portrait,
                referenceFrame: .xArbitraryZVertical,
                requestedFrequencyHz: 100,
                measuredFrequencyHz: 100
            ),
            versions: ProcessingVersionsV3(
                calibrationProfileID: nil,
                calibrationVersion: nil,
                detectorVersion: "debug-recorder/v1",
                analysisVersion: "unanalysed/debug-recorder/v1",
                scoreVersion: nil
            ),
            rawSamples: reference,
            importedExpoAnalysis: nil
        )
        return DebugMotionCaptureExportV1(
            label: DebugMotionCaptureLabel(
                expectedTrickID: .flip,
                gripHand: .right,
                caseState: .withCase,
                condition: .standard,
                outcome: outcome,
                rhythmNotes: "pilot"
            ),
            automaticObservation: nil,
            capture: MotionCaptureV3(attempt: attempt, samplePayload: payload)
        )
    }

    private func sample(sequence: UInt64, timestampS: Double, angle: Double) -> MotionSampleV3 {
        MotionSampleV3(
            sequence: sequence,
            timestampS: timestampS,
            rotationRateRadS: Vector3(x: angle, y: 0, z: 0),
            userAccelerationG: Vector3(x: 0, y: 0.1, z: 0),
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: Quaternion(w: 1, x: angle, y: 0, z: 0)
        )
    }
}
