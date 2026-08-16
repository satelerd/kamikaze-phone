import Foundation
import KamikazeMotionCore
import Testing
@testable import Kamikaze

/// Counts every raw payload decode so tests can prove summary/list flows never
/// touch sensor evidence.
private actor CountingSampleStore: SampleStore {
    private let backing: FileSampleStore
    private(set) var loadCount = 0

    init(backing: FileSampleStore) {
        self.backing = backing
    }

    func store(_ payload: MotionSamplePayloadV3, at reference: RawSampleReferenceV3) async throws {
        try await backing.store(payload, at: reference)
    }

    func load(reference: RawSampleReferenceV3) async throws -> MotionSamplePayloadV3 {
        loadCount += 1
        return try await backing.load(reference: reference)
    }

    func remove(reference: RawSampleReferenceV3) async throws {
        try await backing.remove(reference: reference)
    }
}

struct AttemptSummaryTests {
    private let catalog = TrickCatalog.provisional(gripHand: .right)

    // MARK: - Derivation

    @Test func recognizedDetectorResultSummarizes() throws {
        let capture = try makeCapture(id: "sum-001", timestamp: 10)
        let analysis = AttemptAnalysisRecord(
            attemptID: capture.attempt.id,
            result: makeResult(status: .recognized, trickID: .phoneFlip, fit: 0.91)
        )
        let summary = AttemptSummaryV1(
            attempt: capture.attempt,
            analysis: analysis,
            timezone: TimeZone(identifier: "America/Santiago")
        )
        #expect(summary.trickID == .phoneFlip)
        #expect(summary.isRecognized)
        #expect(summary.fit == 0.91)
        #expect(summary.humanOutcome == nil)
        #expect(summary.interpretationSource == .detector)
        #expect(summary.timezoneIdentifier == "America/Santiago")
        #expect(summary.displayName == "PHONE FLIP")
        #expect(summary.gameScore == nil)
    }

    @Test func reviewStatusHidesProposedIdentity() throws {
        let capture = try makeCapture(id: "sum-002", timestamp: 11)
        let analysis = AttemptAnalysisRecord(
            attemptID: capture.attempt.id,
            result: makeResult(status: .review, trickID: .flip, fit: 0.61)
        )
        let summary = AttemptSummaryV1(attempt: capture.attempt, analysis: analysis)
        #expect(summary.trickID == nil)
        #expect(!summary.isRecognized)
        #expect(summary.displayName == "NEEDS REVIEW")
        // The candidate FIT stays visible as diagnostic context.
        #expect(summary.fit == 0.61)
    }

    @Test func humanCorrectionOverridesDetector() throws {
        let capture = try makeCapture(id: "sum-003", timestamp: 12)
        let result = TrickMatchResult(
            status: .review,
            policyVersion: TrickMatchingPolicy.provisionalVersion,
            catalogVersion: catalog.version,
            features: nil,
            featureIssues: [],
            candidates: [
                makeCandidate(trickID: .flip, fit: 0.66),
                makeCandidate(trickID: .reverseFlip, fit: 0.52),
            ]
        )
        let analysis = AttemptAnalysisRecord(
            attemptID: capture.attempt.id,
            result: result,
            humanReview: HumanAttemptReview(trickID: .reverseFlip, outcome: .landed)
        )
        let summary = AttemptSummaryV1(attempt: capture.attempt, analysis: analysis)
        #expect(summary.trickID == .reverseFlip)
        #expect(summary.isRecognized)
        #expect(summary.hasConfirmedLanding)
        #expect(summary.interpretationSource == .human)
        // FIT follows the human-selected candidate, not the detector's first.
        #expect(summary.fit == 0.52)
    }

    @Test func noAttemptReviewExcludesFromRecognition() throws {
        let capture = try makeCapture(id: "sum-004", timestamp: 13)
        let analysis = AttemptAnalysisRecord(
            attemptID: capture.attempt.id,
            result: makeResult(status: .recognized, trickID: .phoneFlip, fit: 0.88),
            humanReview: HumanAttemptReview(trickID: nil, outcome: .noAttempt)
        )
        let summary = AttemptSummaryV1(attempt: capture.attempt, analysis: analysis)
        #expect(summary.trickID == nil)
        #expect(!summary.isRecognized)
        #expect(!summary.hasConfirmedLanding)
        #expect(summary.displayName == "NO ATTEMPT")
    }

    @Test func durationFallsBackToBoundariesWithoutFeatures() throws {
        let capture = try makeCapture(id: "sum-005", timestamp: 20, motionDurationS: 0.42)
        let analysis = AttemptAnalysisRecord(
            attemptID: capture.attempt.id,
            result: makeResult(status: .unknown, trickID: nil, fit: nil)
        )
        let summary = AttemptSummaryV1(attempt: capture.attempt, analysis: analysis)
        #expect(abs(summary.motionDurationMs - 420) < 0.001)
        #expect(summary.displayName == "UNKNOWN THROW")
    }

    @Test func legacyShuvitIdentifierDecodesCanonically() throws {
        let json = """
        {"schemaVersion":1,"attemptID":"legacy-001","recordedAtISO8601":"2026-08-13T00:00:00Z",\
        "trickID":"backside-shuvit","recognitionStatus":"recognized","motionDurationMs":700,\
        "fit":0.9,"analysisVersion":"x","catalogVersion":"y","sampleCount":2}
        """
        let summary = try CapturePersistenceCodec.decode(AttemptSummaryV1.self, from: Data(json.utf8))
        #expect(summary.trickID == .backsideThreeSixtyShuvit)
    }

    // MARK: - Repository

    @MainActor
    @Test func summariesSurviveRepositoryReload() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileAttemptSummaryRepository(rootDirectory: directory)
        for index in 0 ..< 5 {
            try await repository.upsert(try makeSummary(id: "reload-\(index)", second: index))
        }

        let reloaded = FileAttemptSummaryRepository(rootDirectory: directory)
        let all = try await reloaded.all()
        #expect(all.count == 5)
        // Newest first.
        #expect(all.first?.attemptID == "reload-4")
        #expect(all.last?.attemptID == "reload-0")
    }

    @MainActor
    @Test func paginationBoundsAreExact() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileAttemptSummaryRepository(rootDirectory: directory)
        try await repository.replaceAll(try (0 ..< 7).map { try makeSummary(id: "page-\($0)", second: $0) })

        let first = try await repository.page(offset: 0, limit: 3)
        #expect(first.summaries.map(\.attemptID) == ["page-6", "page-5", "page-4"])
        #expect(first.totalCount == 7)
        #expect(first.hasMore)

        let last = try await repository.page(offset: 6, limit: 3)
        #expect(last.summaries.map(\.attemptID) == ["page-0"])
        #expect(!last.hasMore)

        let beyond = try await repository.page(offset: 7, limit: 3)
        #expect(beyond.summaries.isEmpty)
        #expect(!beyond.hasMore)

        let invalid = try await repository.page(offset: 0, limit: 0)
        #expect(invalid.summaries.isEmpty)
        #expect(invalid.totalCount == 7)
    }

    @MainActor
    @Test func malformedIndexIsTreatedAsRebuildable() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("corrupt".utf8).write(
            to: directory.appending(path: "attempt-summaries.v1.json"),
            options: .atomic
        )
        let repository = FileAttemptSummaryRepository(rootDirectory: directory)
        let all = try await repository.all()
        #expect(all.isEmpty)
    }

    // MARK: - Reconciler

    @MainActor
    @Test func reconcileNeverTouchesRawSamplesWhenAnalysisIsCurrent() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let spy = CountingSampleStore(backing: FileSampleStore(rootDirectory: directory))
        let attempts = FileAttemptRepository(rootDirectory: directory, sampleStore: spy)
        let analyses = FileAttemptAnalysisRepository(rootDirectory: directory)
        let summaries = FileAttemptSummaryRepository(rootDirectory: directory)

        for index in 0 ..< 20 {
            let capture = try makeCapture(id: String(format: "cur-%03d", index), timestamp: Double(index))
            try await attempts.save(capture)
            try await analyses.save(AttemptAnalysisRecord(
                attemptID: capture.attempt.id,
                result: makeResult(status: .recognized, trickID: .phoneFlip, fit: 0.9)
            ))
        }

        let reconciler = AttemptSummaryReconciler(
            attemptRepository: attempts,
            analysisRepository: analyses,
            summaryRepository: summaries,
            catalog: catalog
        )
        let report = try await reconciler.reconcile()
        #expect(report.rebuiltCount == 20)
        #expect(report.issues.isEmpty)
        #expect(await spy.loadCount == 0)

        // Second pass reuses every summary and stays away from raw payloads.
        let second = try await reconciler.reconcile()
        #expect(second.reusedCount == 20)
        #expect(second.rebuiltCount == 0)
        #expect(await spy.loadCount == 0)
    }

    @MainActor
    @Test func staleAnalysisIsRefreshedExactlyOnce() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let spy = CountingSampleStore(backing: FileSampleStore(rootDirectory: directory))
        let attempts = FileAttemptRepository(rootDirectory: directory, sampleStore: spy)
        let analyses = FileAttemptAnalysisRepository(rootDirectory: directory)
        let summaries = FileAttemptSummaryRepository(rootDirectory: directory)

        let capture = try makeCapture(id: "stale-001", timestamp: 1)
        try await attempts.save(capture)
        try await analyses.save(AttemptAnalysisRecord(
            attemptID: capture.attempt.id,
            result: makeResult(
                status: .recognized,
                trickID: .phoneFlip,
                fit: 0.9,
                policyVersion: "rule-matcher-v0.1-obsolete"
            ),
            humanReview: HumanAttemptReview(trickID: .flip, outcome: .landed)
        ))

        let reconciler = AttemptSummaryReconciler(
            attemptRepository: attempts,
            analysisRepository: analyses,
            summaryRepository: summaries,
            catalog: catalog
        )
        let report = try await reconciler.reconcile()
        #expect(report.rebuiltCount == 1)
        #expect(await spy.loadCount == 1)

        // Human evidence survives the machine refresh.
        let all = try await summaries.all()
        #expect(all.first?.humanOutcome == .landed)
        #expect(all.first?.trickID == .flip)

        // The refreshed record is stored, so the cost never repeats.
        try await reconciler.reconcile()
        #expect(await spy.loadCount == 1)
    }

    @MainActor
    @Test func deletedAttemptDropsItsSummary() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let attempts = FileAttemptRepository(rootDirectory: directory)
        let analyses = FileAttemptAnalysisRepository(rootDirectory: directory)
        let summaries = FileAttemptSummaryRepository(rootDirectory: directory)
        try await summaries.upsert(try makeSummary(id: "ghost-001", second: 1))

        let reconciler = AttemptSummaryReconciler(
            attemptRepository: attempts,
            analysisRepository: analyses,
            summaryRepository: summaries,
            catalog: catalog
        )
        let report = try await reconciler.reconcile()
        #expect(report.removedCount == 1)
        #expect(try await summaries.all().isEmpty)
    }

    // MARK: - Scale gate (G1 acceptance)

    @MainActor
    @Test func oneThousandAttemptsReconcileAndPageWithoutRawDecodes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let spy = CountingSampleStore(backing: FileSampleStore(rootDirectory: directory))
        let attempts = FileAttemptRepository(rootDirectory: directory, sampleStore: spy)
        let analyses = FileAttemptAnalysisRepository(rootDirectory: directory)
        let summaries = FileAttemptSummaryRepository(rootDirectory: directory)

        // Seed the attempt index directly: repeated `save` calls rewrite the
        // whole index per attempt, which is not what this gate measures.
        var metadata: [MotionAttemptV3] = []
        for index in 0 ..< 1_000 {
            let capture = try makeCapture(id: String(format: "scale-%04d", index), timestamp: Double(index))
            metadata.append(capture.attempt)
            try await analyses.save(AttemptAnalysisRecord(
                attemptID: capture.attempt.id,
                result: makeResult(status: .recognized, trickID: .phoneFlip, fit: 0.9)
            ))
        }
        try AtomicFileWriter.write(
            try CapturePersistenceCodec.encode(metadata),
            to: directory.appending(path: "attempt-index.v3.json")
        )

        let reconciler = AttemptSummaryReconciler(
            attemptRepository: attempts,
            analysisRepository: analyses,
            summaryRepository: summaries,
            catalog: catalog
        )

        let clock = ContinuousClock()
        let start = clock.now
        let report = try await reconciler.reconcile()
        var offset = 0
        var rows = 0
        while true {
            let page = try await summaries.page(offset: offset, limit: ProfileModel.pageSize)
            rows += page.summaries.count
            offset += page.summaries.count
            if !page.hasMore { break }
        }
        let elapsed = clock.now - start

        #expect(report.rebuiltCount == 1_000)
        #expect(report.issues.isEmpty)
        #expect(rows == 1_000)
        // The G1 gate: listing and paging summaries decodes zero raw payloads.
        #expect(await spy.loadCount == 0)
        #expect(elapsed < .seconds(5))
    }

    // MARK: - Helpers

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "KamikazeAttemptSummaryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeCandidate(trickID: BuiltInTrickID, fit: Double) -> TrickMatchCandidate {
        TrickMatchCandidate(
            definition: TrickDefinition(
                id: trickID,
                displayName: trickID.displayName,
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
        )
    }

    private func makeResult(
        status: TrickRecognitionStatus,
        trickID: BuiltInTrickID?,
        fit: Double?,
        policyVersion: String = TrickMatchingPolicy.provisionalVersion
    ) -> TrickMatchResult {
        TrickMatchResult(
            status: status,
            policyVersion: policyVersion,
            catalogVersion: catalog.version,
            features: nil,
            featureIssues: [],
            candidates: trickID.map { [makeCandidate(trickID: $0, fit: fit ?? 0)] } ?? []
        )
    }

    private func makeSummary(id: String, second: Int) throws -> AttemptSummaryV1 {
        let capture = try makeCapture(id: id, timestamp: Double(second))
        return AttemptSummaryV1(
            attempt: capture.attempt,
            analysis: AttemptAnalysisRecord(
                attemptID: id,
                result: makeResult(status: .recognized, trickID: .phoneFlip, fit: 0.9)
            ),
            timezone: TimeZone(identifier: "America/Santiago")
        )
    }

    private func makeCapture(
        id: String,
        timestamp: Double,
        motionDurationS: Double = 0.01
    ) throws -> MotionCaptureV3 {
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
                timestampS: timestamp + motionDurationS,
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
        let seconds = second(from: timestamp)
        let attempt = MotionAttemptV3(
            id: id,
            source: .sensor,
            recordedAtISO8601: seconds,
            captureMode: .manual,
            triggerMode: nil,
            boundaries: AttemptBoundariesV3(
                captureStartS: timestamp,
                captureEndS: timestamp + motionDurationS,
                motionStartS: timestamp,
                motionEndS: timestamp + motionDurationS,
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

    /// Monotonic ISO strings so ordering assertions stay unambiguous.
    private func second(from timestamp: Double) -> String {
        let total = Int(timestamp)
        return String(
            format: "2026-08-13T%02d:%02d:%02dZ",
            (total / 3_600) % 24,
            (total / 60) % 60,
            total % 60
        )
    }
}
