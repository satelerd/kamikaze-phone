import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct PracticeProgressTests {
    private let catalog = TrickCatalog.provisional(gripHand: .right)

    @Test func qualifyingRepRequiresTargetIdentityAndHumanLanding() throws {
        let progress = PracticeProgress(summaries: [
            // Counts: right trick, human landed.
            try summary(id: "q1", second: 5, trick: .flip, outcome: .landed),
            // Wrong trick.
            try summary(id: "q2", second: 4, trick: .reverseFlip, outcome: .landed),
            // Right trick, human said missed.
            try summary(id: "q3", second: 3, trick: .flip, outcome: .missed),
            // Detector recognized but nobody confirmed the landing.
            try summary(id: "q4", second: 2, trick: .flip, outcome: nil),
        ])
        #expect(progress.qualifyingReps(for: .flip) == 1)
        #expect(progress.attemptCount(for: .flip) == 3)
        #expect(!progress.isUnlockedByReps(.flip))
    }

    @Test func firstDetectorReadyPairIsPlayableFromZero() {
        let progress = PracticeProgress(summaries: [])
        let shuvit180 = PracticeLibrary.pairs[0]
        let fullShuvit = PracticeLibrary.pairs[1]
        let flip = PracticeLibrary.pairs[2]

        // Collection-only pairs are never scored-playable…
        #expect(!progress.isPairUnlocked(shuvit180))
        // …and they do not block the ladder behind them.
        #expect(progress.isPairUnlocked(fullShuvit))
        // The next detector-ready pair waits for mastery of the previous one.
        #expect(!progress.isPairUnlocked(flip))
    }

    @Test func masteringAPairUnlocksTheNextDetectorReadyPair() throws {
        var rows: [AttemptSummaryV1] = []
        var second = 60
        for trick in [BuiltInTrickID.backsideThreeSixtyShuvit, .frontsideThreeSixtyShuvit] {
            for index in 0 ..< 3 {
                rows.append(try summary(id: "m-\(trick.rawValue)-\(index)", second: second, trick: trick, outcome: .landed))
                second -= 1
            }
        }
        let progress = PracticeProgress(summaries: rows)
        let fullShuvit = PracticeLibrary.pairs[1]
        let flip = PracticeLibrary.pairs[2]
        let phoneFlip = PracticeLibrary.pairs[4]

        #expect(progress.isPairMastered(fullShuvit))
        #expect(progress.isPairUnlocked(flip))
        // Phone Flip still waits for the Flip pair.
        #expect(!progress.isPairUnlocked(phoneFlip))
    }

    @Test func oppositeDirectionWaitsForPrimaryReps() throws {
        let fullShuvit = PracticeLibrary.pairs[1]
        let empty = PracticeProgress(summaries: [])
        #expect(empty.isTrickUnlocked(.backsideThreeSixtyShuvit, in: fullShuvit))
        #expect(!empty.isTrickUnlocked(.frontsideThreeSixtyShuvit, in: fullShuvit))

        let progressed = PracticeProgress(summaries: try (0 ..< 3).map {
            try summary(id: "bs-\($0)", second: 10 + $0, trick: .backsideThreeSixtyShuvit, outcome: .landed)
        })
        #expect(progressed.isTrickUnlocked(.frontsideThreeSixtyShuvit, in: fullShuvit))
    }

    @Test func masteryLivesInTheLatestFiveAttempts() throws {
        // Newest-first: five recent misses, then three old landed reps.
        var rows: [AttemptSummaryV1] = []
        for index in 0 ..< 5 {
            rows.append(try summary(id: "recent-\(index)", second: 100 - index, trick: .flip, outcome: .missed))
        }
        for index in 0 ..< 3 {
            rows.append(try summary(id: "old-\(index)", second: 50 - index, trick: .flip, outcome: .landed))
        }
        let progress = PracticeProgress(summaries: rows)
        // Total reps still unlock the next node…
        #expect(progress.isUnlockedByReps(.flip))
        // …but current mastery is judged on the latest window.
        #expect(!progress.isMastered(.flip))
    }

    // MARK: - Helpers

    private func summary(
        id: String,
        second: Int,
        trick: BuiltInTrickID,
        outcome: HumanAttemptOutcome?
    ) throws -> AttemptSummaryV1 {
        let capture = try TestCaptureFactory.makeCapture(id: id, timestamp: Double(second))
        let result = TrickMatchResult(
            status: .recognized,
            policyVersion: TrickMatchingPolicy.provisionalVersion,
            catalogVersion: catalog.version,
            features: nil,
            featureIssues: [],
            candidates: [TrickMatchCandidate(
                definition: TrickDefinition(
                    id: trick,
                    displayName: trick.displayName,
                    family: .flip,
                    targetRotationDegrees: Vector3(x: 0, y: 360, z: 0),
                    referenceDurationMs: 700
                ),
                presentationFit: 0.9,
                rotationFit: 0.9,
                axisPurity: 0.8,
                durationFit: 0.8,
                minimumAxisCoverage: 1,
                axesAreSeparable: true
            )]
        )
        let review = outcome.map { HumanAttemptReview(trickID: $0 == .noAttempt ? nil : trick, outcome: $0) }
        return AttemptSummaryV1(
            attempt: capture.attempt,
            analysis: AttemptAnalysisRecord(attemptID: id, result: result, humanReview: review)
        )
    }
}

/// Shared minimal capture builder for tests that need valid metadata but no
/// meaningful physics.
enum TestCaptureFactory {
    static func makeCapture(id: String, timestamp: Double) throws -> MotionCaptureV3 {
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
        let total = Int(timestamp)
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: String(
                format: "2026-08-14T%02d:%02d:%02dZ",
                (total / 3_600) % 24,
                (total / 60) % 60,
                total % 60
            ),
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
            rawSamples: RawSampleReferenceV3(
                relativePath: "samples/\(id).json",
                encoding: .json,
                payloadSchemaVersion: MotionSchemaV3.version,
                sampleCount: samples.count,
                checksum: CapturePersistenceCodec.sha256(try CapturePersistenceCodec.encode(payload))
            ),
            importedExpoAnalysis: nil
        )
        return MotionCaptureV3(attempt: attempt, samplePayload: payload)
    }
}
