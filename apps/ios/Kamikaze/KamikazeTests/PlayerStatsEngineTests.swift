import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct PlayerStatsEngineTests {
    private let catalog = TrickCatalog.provisional(gripHand: .right)
    private let santiago = TimeZone(identifier: "America/Santiago")!

    @Test func perTrickStatsUseLandedOnlyDurations() throws {
        let engine = PlayerStatsEngine(summaries: [
            try summary(id: "t1", second: 40, trick: .flip, outcome: .landed, durationS: 0.700, fit: 0.90),
            try summary(id: "t2", second: 39, trick: .flip, outcome: .landed, durationS: 0.500, fit: 0.85),
            // Missed attempts never contribute to fastest/longest records.
            try summary(id: "t3", second: 38, trick: .flip, outcome: .missed, durationS: 0.100, fit: 0.60),
            try summary(id: "t4", second: 37, trick: .phoneFlip, outcome: nil, durationS: 0.900, fit: 0.88),
        ], defaultTimezone: santiago)

        let flip = try #require(engine.trickStats.first { $0.trickID == .flip })
        #expect(flip.attemptCount == 3)
        #expect(flip.landedCount == 2)
        #expect(flip.bestFitPercent == 90)
        #expect(flip.fastestLandedMs == 500)
        #expect(flip.longestLandedMs == 700)

        let phone = try #require(engine.trickStats.first { $0.trickID == .phoneFlip })
        #expect(phone.landedCount == 0)
        #expect(phone.fastestLandedMs == nil)

        // Tricks with landings rank above unlanded ones.
        #expect(engine.trickStats.first?.trickID == .flip)
    }

    @Test func recordsLinkToTheirAttempts() throws {
        let engine = PlayerStatsEngine(summaries: [
            try summary(id: "r-fast", second: 30, trick: .flip, outcome: .landed, durationS: 0.404, fit: 0.80),
            try summary(id: "r-long", second: 29, trick: .phoneFlip, outcome: .landed, durationS: 1.250, fit: 0.82),
            try summary(id: "r-fit", second: 28, trick: .reverseFlip, outcome: nil, durationS: 0.800, fit: 0.95),
        ], defaultTimezone: santiago)

        #expect(engine.fastestLanded?.attemptID == "r-fast")
        #expect(engine.fastestLanded?.valueLabel == "404 MS")
        #expect(engine.longestLanded?.attemptID == "r-long")
        #expect(engine.bestFit?.attemptID == "r-fit")
        #expect(engine.bestFit?.valueLabel == "95 FIT")
    }

    @Test func activityDaysFollowTheStoredTimezone() throws {
        // 2026-08-14T01:30Z is still 2026-08-13 in Santiago (UTC-4).
        let lateNight = try summary(
            id: "a1", second: 0, trick: .flip, outcome: .landed, durationS: 0.6, fit: 0.9,
            recordedAt: "2026-08-14T01:30:00Z", timezone: santiago
        )
        // Same instant without a stored timezone falls back to the default.
        let utc = TimeZone(identifier: "UTC")!
        let legacy = try summary(
            id: "a2", second: 0, trick: .flip, outcome: .landed, durationS: 0.6, fit: 0.9,
            recordedAt: "2026-08-14T01:30:00Z", timezone: nil
        )

        let engine = PlayerStatsEngine(summaries: [lateNight, legacy], defaultTimezone: utc)
        #expect(engine.activity(onDayKey: "2026-08-13") == 1)
        #expect(engine.activity(onDayKey: "2026-08-14") == 1)
        #expect(engine.activeDayCount == 2)
    }

    @Test func emptyEvidenceProducesEmptyStats() {
        let engine = PlayerStatsEngine(summaries: [], defaultTimezone: santiago)
        #expect(engine.trickStats.isEmpty)
        #expect(engine.fastestLanded == nil)
        #expect(engine.bestFit == nil)
        #expect(engine.activeDayCount == 0)
    }

    // MARK: - Helpers

    private func summary(
        id: String,
        second: Int,
        trick: BuiltInTrickID,
        outcome: HumanAttemptOutcome?,
        durationS: Double,
        fit: Double,
        recordedAt: String? = nil,
        timezone: TimeZone? = TimeZone(identifier: "America/Santiago")
    ) throws -> AttemptSummaryV1 {
        var capture = try TestCaptureFactory.makeCapture(id: id, timestamp: Double(second))
        if let recordedAt {
            capture = MotionCaptureV3(
                attempt: MotionAttemptV3(
                    id: capture.attempt.id,
                    source: capture.attempt.source,
                    recordedAtISO8601: recordedAt,
                    captureMode: capture.attempt.captureMode,
                    triggerMode: capture.attempt.triggerMode,
                    boundaries: capture.attempt.boundaries,
                    environment: capture.attempt.environment,
                    versions: capture.attempt.versions,
                    rawSamples: capture.attempt.rawSamples,
                    importedExpoAnalysis: capture.attempt.importedExpoAnalysis
                ),
                samplePayload: capture.samplePayload
            )
        }
        let result = TrickMatchResult(
            status: .recognized,
            policyVersion: TrickMatchingPolicy.provisionalVersion,
            catalogVersion: catalog.version,
            features: MotionFeatures(
                motionDurationMs: durationS * 1_000,
                signedRotationDegrees: Vector3(x: 0, y: 360, z: 0),
                angularPathDegrees: Vector3(x: 0, y: 360, z: 0),
                totalAngularPathDegrees: 360,
                fusedAttitudeRotationDegrees: nil,
                gyroFusedAgreement: nil,
                fusedComparisonSampleCount: 0,
                peakGyroDps: 600,
                minimumAccelerationG: nil,
                peakAccelerationG: nil,
                peakCatchAccelerationG: nil,
                postCatchStability: 0.05,
                dominantAxisPurity: 1,
                rotationEfficiency: 1
            ),
            featureIssues: [],
            candidates: [TrickMatchCandidate(
                definition: TrickDefinition(
                    id: trick,
                    displayName: trick.displayName,
                    family: .flip,
                    targetRotationDegrees: Vector3(x: 0, y: 360, z: 0),
                    referenceDurationMs: 700
                ),
                presentationFit: fit,
                rotationFit: fit,
                axisPurity: 0.8,
                durationFit: 0.8,
                minimumAxisCoverage: 1,
                axesAreSeparable: true
            )]
        )
        let review = outcome.map {
            HumanAttemptReview(trickID: $0 == .noAttempt ? nil : trick, outcome: $0)
        }
        return AttemptSummaryV1(
            attempt: capture.attempt,
            analysis: AttemptAnalysisRecord(attemptID: id, result: result, humanReview: review),
            timezone: timezone
        )
    }
}
