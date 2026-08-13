import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct PlayerFeedbackExportTests {
    @MainActor
    @Test func correctedIdentityNeverKeepsAnotherTricksFit() throws {
        let definitions = TrickCatalog.provisional(gripHand: .right).definitions
        let flip = try #require(definitions.first { $0.id == .flip })
        let phoneFlip = try #require(definitions.first { $0.id == .phoneFlip })
        let candidates = [
            makeCandidate(definition: flip, fit: 0.88),
            makeCandidate(definition: phoneFlip, fit: 0.63),
        ]
        let match = TrickMatchResult(
            status: .recognized,
            policyVersion: "policy-test",
            catalogVersion: "catalog-test",
            features: nil,
            featureIssues: [],
            candidates: candidates
        )
        let capture = try makeCapture(id: "fit-001")

        let automatic = NativeRunResult(capture: capture, match: match)
        let correctedCandidate = automatic.replacingHumanReview(HumanAttemptReview(
            trickID: .phoneFlip,
            outcome: .landed
        ))
        let correctedOutsideTopThree = automatic.replacingHumanReview(HumanAttemptReview(
            trickID: .frontsideShuvit,
            outcome: .landed
        ))

        #expect(automatic.displayedFit == 88)
        #expect(correctedCandidate.displayedFit == 63)
        #expect(correctedOutsideTopThree.displayedFit == nil)
    }

    @MainActor
    @Test func exportsOnlyHumanReviewedAttemptsWithRawEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazePlayerFeedbackTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let reviewedCapture = try makeCapture(id: "reviewed-001")
        let unreviewedCapture = try makeCapture(id: "unreviewed-001")
        let match = TrickMatchResult(
            status: .recognized,
            policyVersion: "policy-test",
            catalogVersion: "catalog-test",
            features: nil,
            featureIssues: [],
            candidates: []
        )
        let review = HumanAttemptReview(
            trickID: .flip,
            outcome: .landed,
            reviewedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let results = [
            NativeRunResult(capture: reviewedCapture, match: match, humanReview: review),
            NativeRunResult(capture: unreviewedCapture, match: match),
        ]

        let exportedURL = try PlayerFeedbackExporter.export(
            results: results,
            rootDirectory: directory
        )
        let url = try #require(exportedURL)
        let decoded = try CapturePersistenceCodec.decode(
            PlayerFeedbackDatasetV1.self,
            from: Data(contentsOf: url)
        )

        #expect(decoded.format == "kamikaze.player-feedback.v1")
        #expect(decoded.captures.count == 1)
        #expect(decoded.captures.first?.capture == reviewedCapture)
        #expect(decoded.captures.first?.humanReview == review)
        #expect(decoded.captures.first?.machineResult == match)
    }

    @MainActor
    @Test func returnsNoExportWhenNothingHasBeenReviewed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeEmptyFeedbackTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = NativeRunResult(
            capture: try makeCapture(id: "unreviewed-002"),
            match: TrickMatchResult(
                status: .unknown,
                policyVersion: "policy-test",
                catalogVersion: "catalog-test",
                features: nil,
                featureIssues: [],
                candidates: []
            )
        )

        #expect(try PlayerFeedbackExporter.export(results: [result], rootDirectory: directory) == nil)
    }

    private func makeCapture(id: String) throws -> MotionCaptureV3 {
        let samples = [MotionSampleV3(
            sequence: 0,
            timestampS: 10,
            rotationRateRadS: Vector3(x: 0, y: 1, z: 0),
            userAccelerationG: Vector3(x: 0, y: 0, z: 0),
            gravityG: Vector3(x: 0, y: 0, z: 1),
            fusedAttitude: .identity
        )]
        let payload = MotionSamplePayloadV3(attemptID: id, samples: samples)
        let raw = RawSampleReferenceV3(
            relativePath: "raw/\(id).json",
            encoding: .json,
            payloadSchemaVersion: MotionSchemaV3.version,
            sampleCount: samples.count,
            checksum: CapturePersistenceCodec.sha256(try CapturePersistenceCodec.encode(payload))
        )
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: "2026-08-13T00:00:00Z",
            captureMode: .auto,
            triggerMode: .gyro,
            boundaries: AttemptBoundariesV3(
                captureStartS: 10,
                captureEndS: 10,
                motionStartS: 10,
                motionEndS: 10,
                releaseS: nil,
                catchS: nil,
                settledS: nil
            ),
            environment: CaptureEnvironmentV3(
                device: CaptureDeviceMetadataV3(
                    modelIdentifier: "test",
                    modelName: "Test iPhone",
                    operatingSystemName: "iOS",
                    operatingSystemVersion: "26",
                    operatingSystemBuild: nil
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
                detectorVersion: "test",
                analysisVersion: "test",
                scoreVersion: nil
            ),
            rawSamples: raw,
            importedExpoAnalysis: nil
        )
        return MotionCaptureV3(attempt: attempt, samplePayload: payload)
    }

    private func makeCandidate(
        definition: TrickDefinition,
        fit: Double
    ) -> TrickMatchCandidate {
        TrickMatchCandidate(
            definition: definition,
            presentationFit: fit,
            rotationFit: fit,
            axisPurity: fit,
            durationFit: fit,
            minimumAxisCoverage: fit,
            axesAreSeparable: true
        )
    }
}
