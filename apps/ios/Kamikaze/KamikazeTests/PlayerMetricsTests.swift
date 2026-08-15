import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct PlayerMetricsTests {
    private let catalog = TrickCatalog.provisional(gripHand: .right)

    @Test func currentStreakBreaksOnMissAndSkipsNeutralEvidence() throws {
        // Newest-first: landed, landed, unreviewed, landed, missed, landed.
        let metrics = PlayerMetrics(summaries: [
            try summary(id: "s1", second: 60, outcome: .landed),
            try summary(id: "s2", second: 59, outcome: .landed),
            try summary(id: "s3", second: 58, outcome: nil),
            try summary(id: "s4", second: 57, outcome: .landed),
            try summary(id: "s5", second: 56, outcome: .missed),
            try summary(id: "s6", second: 55, outcome: .landed),
        ])
        // The unreviewed attempt waits for review: it neither counts nor breaks.
        #expect(metrics.currentStreak == 3)
        #expect(metrics.bestStreak == 3)
        #expect(metrics.landedCount == 4)
    }

    @Test func noAttemptIsIgnoredEverywhere() throws {
        let metrics = PlayerMetrics(summaries: [
            try summary(id: "n1", second: 30, outcome: .landed),
            try summary(id: "n2", second: 29, outcome: .noAttempt),
            try summary(id: "n3", second: 28, outcome: .landed),
        ])
        #expect(metrics.currentStreak == 2)
        #expect(metrics.attemptCount == 2)
        #expect(metrics.landedCount == 2)
    }

    @Test func freshMissMeansZeroStreakDespiteHistory() throws {
        let metrics = PlayerMetrics(summaries: [
            try summary(id: "z1", second: 20, outcome: .missed),
            try summary(id: "z2", second: 19, outcome: .landed),
            try summary(id: "z3", second: 18, outcome: .landed),
        ])
        #expect(metrics.currentStreak == 0)
        #expect(metrics.bestStreak == 2)
    }

    @MainActor
    @Test func deletionRemovesEvidenceInterpretationAndSummary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeDeletionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let attempts = FileAttemptRepository(rootDirectory: directory)
        let analyses = FileAttemptAnalysisRepository(rootDirectory: directory)
        let summaries = FileAttemptSummaryRepository(rootDirectory: directory)

        let capture = try TestCaptureFactory.makeCapture(id: "del-001", timestamp: 5)
        try await attempts.save(capture)
        let record = AttemptAnalysisRecord(attemptID: capture.attempt.id, result: makeResult())
        try await analyses.save(record)
        try await summaries.upsert(AttemptSummaryV1(attempt: capture.attempt, analysis: record))

        let rawURL = directory.appending(path: capture.attempt.rawSamples.relativePath)
        #expect(FileManager.default.fileExists(atPath: rawURL.path))

        try await attempts.delete(id: capture.attempt.id)
        try await analyses.delete(attemptID: capture.attempt.id)
        try await summaries.remove(attemptID: capture.attempt.id)

        #expect(!FileManager.default.fileExists(atPath: rawURL.path))
        #expect(try await attempts.list().isEmpty)
        #expect(try await analyses.load(attemptID: capture.attempt.id) == nil)
        #expect(try await summaries.all().isEmpty)

        // Deleting again is a safe no-op, so an interrupted transaction can
        // simply be retried.
        try await attempts.delete(id: capture.attempt.id)

        // The reconciler agrees the world is empty.
        let reconciler = AttemptSummaryReconciler(
            attemptRepository: attempts,
            analysisRepository: analyses,
            summaryRepository: summaries,
            catalog: catalog
        )
        let report = try await reconciler.reconcile()
        #expect(report.reusedCount == 0)
        #expect(report.rebuiltCount == 0)
    }

    // MARK: - Helpers

    private func makeResult() -> TrickMatchResult {
        TrickMatchResult(
            status: .recognized,
            policyVersion: TrickMatchingPolicy.provisionalVersion,
            catalogVersion: catalog.version,
            features: nil,
            featureIssues: [],
            candidates: [TrickMatchCandidate(
                definition: TrickDefinition(
                    id: .flip,
                    displayName: "FLIP",
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
    }

    private func summary(
        id: String,
        second: Int,
        outcome: HumanAttemptOutcome?
    ) throws -> AttemptSummaryV1 {
        let capture = try TestCaptureFactory.makeCapture(id: id, timestamp: Double(second))
        let review = outcome.map {
            HumanAttemptReview(trickID: $0 == .noAttempt ? nil : .flip, outcome: $0)
        }
        return AttemptSummaryV1(
            attempt: capture.attempt,
            analysis: AttemptAnalysisRecord(attemptID: id, result: makeResult(), humanReview: review)
        )
    }
}
