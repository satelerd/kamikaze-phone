import Foundation
import KamikazeMotionCore

nonisolated struct AttemptSummaryPage: Equatable, Sendable {
    let summaries: [AttemptSummaryV1]
    let totalCount: Int
    let offset: Int

    var hasMore: Bool { offset + summaries.count < totalCount }
}

protocol AttemptSummaryRepository: Sendable {
    func page(offset: Int, limit: Int) async throws -> AttemptSummaryPage
    func all() async throws -> [AttemptSummaryV1]
    func upsert(_ summary: AttemptSummaryV1) async throws
    func remove(attemptID: String) async throws
    func replaceAll(_ summaries: [AttemptSummaryV1]) async throws
}

/// One JSON index file for every summary. Summaries are small enough that the
/// whole index stays in memory; pagination bounds what the UI materializes,
/// not what the actor holds.
actor FileAttemptSummaryRepository: AttemptSummaryRepository {
    private nonisolated struct IndexFileV1: Codable {
        static let schemaVersion = 1
        let schemaVersion: Int
        let entries: [AttemptSummaryV1]
    }

    private let indexURL: URL
    private var cache: [AttemptSummaryV1]?

    init(rootDirectory: URL) {
        indexURL = rootDirectory.standardizedFileURL.appending(path: "attempt-summaries.v1.json")
    }

    func page(offset: Int, limit: Int) throws -> AttemptSummaryPage {
        let entries = try loadSorted()
        guard offset >= 0, limit > 0, offset < entries.count else {
            return AttemptSummaryPage(summaries: [], totalCount: entries.count, offset: max(0, offset))
        }
        let slice = Array(entries[offset ..< min(offset + limit, entries.count)])
        return AttemptSummaryPage(summaries: slice, totalCount: entries.count, offset: offset)
    }

    func all() throws -> [AttemptSummaryV1] {
        try loadSorted()
    }

    func upsert(_ summary: AttemptSummaryV1) throws {
        var entries = try loadSorted()
        entries.removeAll { $0.attemptID == summary.attemptID }
        entries.append(summary)
        try persist(entries)
    }

    func remove(attemptID: String) throws {
        var entries = try loadSorted()
        entries.removeAll { $0.attemptID == attemptID }
        try persist(entries)
    }

    func replaceAll(_ summaries: [AttemptSummaryV1]) throws {
        try persist(summaries)
    }

    private func loadSorted() throws -> [AttemptSummaryV1] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            cache = []
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: indexURL)
        } catch {
            throw AttemptPersistenceError.ioFailure
        }
        guard let file = try? CapturePersistenceCodec.decode(IndexFileV1.self, from: data),
              file.schemaVersion == IndexFileV1.schemaVersion else {
            // A malformed or future-version index is rebuildable state, never
            // evidence. Treat it as absent so the reconciler regenerates it.
            cache = []
            return []
        }
        let sorted = Self.sorted(file.entries)
        cache = sorted
        return sorted
    }

    private func persist(_ entries: [AttemptSummaryV1]) throws {
        let sorted = Self.sorted(entries)
        let data = try CapturePersistenceCodec.encode(
            IndexFileV1(schemaVersion: IndexFileV1.schemaVersion, entries: sorted)
        )
        try AtomicFileWriter.write(data, to: indexURL)
        cache = sorted
    }

    /// Mirrors `FileAttemptRepository.list()` ordering: newest first.
    private nonisolated static func sorted(_ entries: [AttemptSummaryV1]) -> [AttemptSummaryV1] {
        entries.sorted {
            if $0.recordedAtISO8601 == $1.recordedAtISO8601 { return $0.attemptID > $1.attemptID }
            return $0.recordedAtISO8601 > $1.recordedAtISO8601
        }
    }
}

nonisolated struct AttemptSummaryReconcileReport: Equatable, Sendable {
    var reusedCount = 0
    var rebuiltCount = 0
    var removedCount = 0
    var issues: [String] = []
}

/// Brings the summary index in line with the attempt index. The fast path — no
/// new attempts and a current analysis version — reads two index files and
/// touches no raw payload. Raw samples are decoded only to refresh a stale or
/// missing analysis, once per attempt, and the refreshed record is stored so
/// the cost never repeats.
nonisolated struct AttemptSummaryReconciler: Sendable {
    let attemptRepository: any AttemptRepository
    let analysisRepository: any AttemptAnalysisRepository
    let summaryRepository: any AttemptSummaryRepository
    let matcher: TrickMatcher
    let catalog: TrickCatalog
    let timezone: TimeZone

    init(
        attemptRepository: any AttemptRepository,
        analysisRepository: any AttemptAnalysisRepository,
        summaryRepository: any AttemptSummaryRepository,
        matcher: TrickMatcher = TrickMatcher(),
        catalog: TrickCatalog = TrickCatalog.provisional(gripHand: .right),
        timezone: TimeZone = .current
    ) {
        self.attemptRepository = attemptRepository
        self.analysisRepository = analysisRepository
        self.summaryRepository = summaryRepository
        self.matcher = matcher
        self.catalog = catalog
        self.timezone = timezone
    }

    @discardableResult
    func reconcile() async throws -> AttemptSummaryReconcileReport {
        let attempts = try await attemptRepository.list()
        let existing = try await summaryRepository.all()
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.attemptID, $0) })
        let attemptIDs = Set(attempts.map(\.id))

        var report = AttemptSummaryReconcileReport()
        var next: [AttemptSummaryV1] = []
        next.reserveCapacity(attempts.count)

        for attempt in attempts {
            if let current = existingByID[attempt.id],
               current.schemaVersion == AttemptSummaryV1.schemaVersion,
               current.analysisVersion == TrickMatchingPolicy.provisionalVersion,
               current.catalogVersion == catalog.version,
               current.scoreVersion == GameScoreEngine.version {
                next.append(current)
                report.reusedCount += 1
                continue
            }
            do {
                let analysis = try await currentAnalysis(for: attempt)
                next.append(AttemptSummaryV1(attempt: attempt, analysis: analysis, timezone: timezone))
                report.rebuiltCount += 1
            } catch {
                // The raw evidence stays untouched on disk; only its summary is
                // unavailable. Surfacing the ID keeps the failure visible.
                report.issues.append("\(attempt.id): \(error)")
            }
        }

        report.removedCount = existing.count { !attemptIDs.contains($0.attemptID) }
        if next != existing {
            try await summaryRepository.replaceAll(next)
        }
        return report
    }

    private func currentAnalysis(for attempt: MotionAttemptV3) async throws -> AttemptAnalysisRecord {
        let stored = try await analysisRepository.load(attemptID: attempt.id)
        if let stored,
           stored.schemaVersion == AttemptAnalysisRecord.schemaVersion,
           stored.result.policyVersion == TrickMatchingPolicy.provisionalVersion,
           stored.result.catalogVersion == catalog.version {
            return stored
        }

        let capture = try await attemptRepository.load(id: attempt.id)
        let trigger: AttemptSegmentationTrigger = attempt.triggerMode == .freefall ? .freefall : .gyro
        let segmented = SegmentedAttemptV3(
            captureMode: attempt.captureMode,
            trigger: trigger,
            boundaries: attempt.boundaries,
            samples: capture.samplePayload.samples,
            timedOut: false
        )
        let refreshed = AttemptAnalysisRecord(
            attemptID: attempt.id,
            result: matcher.match(attempt: segmented, catalog: catalog),
            humanReview: stored?.humanReview
        )
        try await analysisRepository.save(refreshed)
        return refreshed
    }
}
