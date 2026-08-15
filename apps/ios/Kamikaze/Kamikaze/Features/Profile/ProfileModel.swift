import Foundation
import KamikazeMotionCore
import Observation

@MainActor
@Observable
final class ProfileModel {
    static let pageSize = 20

    private let attemptRepository: FileAttemptRepository
    private let analysisRepository: FileAttemptAnalysisRepository
    private let summaryRepository: FileAttemptSummaryRepository
    private let reconciler: AttemptSummaryReconciler
    private let rootDirectory: URL

    /// Summary rows the UI has materialized so far, newest first.
    private(set) var visible: [AttemptSummaryV1] = []
    private(set) var totalCount = 0
    /// Full summary index for statistics. Summaries are small; raw sample
    /// payloads are never decoded to compute these.
    private(set) var allSummaries: [AttemptSummaryV1] = []
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isOpeningAttempt = false
    private(set) var reviewedCount = 0

    private(set) var isExportingFeedback = false
    private(set) var feedbackExportURL: URL?
    private(set) var feedbackExportError: String?

    init(rootDirectory: URL = AttemptStorageLocation.applicationRoot()) {
        self.rootDirectory = rootDirectory
        let attempts = FileAttemptRepository(rootDirectory: rootDirectory)
        let analyses = FileAttemptAnalysisRepository(rootDirectory: rootDirectory)
        let summaries = FileAttemptSummaryRepository(rootDirectory: rootDirectory)
        attemptRepository = attempts
        analysisRepository = analyses
        summaryRepository = summaries
        reconciler = AttemptSummaryReconciler(
            attemptRepository: attempts,
            analysisRepository: analyses,
            summaryRepository: summaries
        )
    }

    var recognizedCount: Int {
        allSummaries.count(where: \.isRecognized)
    }

    var confirmedLandedCount: Int {
        allSummaries.count(where: \.hasConfirmedLanding)
    }

    var highFit: Int? {
        allSummaries
            .filter(\.isRecognized)
            .compactMap(\.fit)
            .max()
            .map { Int(($0 * 100).rounded()) }
    }

    var bestRun: Int {
        var best = 0
        var current = 0
        for summary in allSummaries.reversed() {
            if summary.isRecognized {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    var hasMore: Bool { visible.count < totalCount }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let report = try await reconciler.reconcile()
            let summaries = try await summaryRepository.all()
            allSummaries = summaries
            totalCount = summaries.count
            reviewedCount = summaries.count { $0.humanOutcome != nil }
            let firstPageCount = max(Self.pageSize, min(visible.count, summaries.count))
            visible = Array(summaries.prefix(firstPageCount))
            loadError = report.issues.isEmpty
                ? nil
                : "\(report.issues.count) attempt(s) could not be summarized. Raw evidence is untouched."
        } catch {
            loadError = error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await summaryRepository.page(offset: visible.count, limit: Self.pageSize)
            visible.append(contentsOf: page.summaries)
            totalCount = page.totalCount
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Raw samples are decoded here and only here, when one attempt opens.
    func openAttempt(id: String) async -> NativeRunResult? {
        guard !isOpeningAttempt else { return nil }
        isOpeningAttempt = true
        defer { isOpeningAttempt = false }
        do {
            let capture = try await attemptRepository.load(id: id)
            guard let analysis = try await analysisRepository.load(attemptID: id) else {
                loadError = "Attempt \(id) has no analysis record."
                return nil
            }
            return NativeRunResult(
                capture: capture,
                match: analysis.result,
                humanReview: analysis.humanReview
            )
        } catch {
            loadError = error.localizedDescription
            return nil
        }
    }

    func applyHumanReview(
        attemptID: String,
        review: HumanAttemptReview,
        current: NativeRunResult
    ) async -> NativeRunResult? {
        let updated = current.replacingHumanReview(review)
        do {
            let record = AttemptAnalysisRecord(
                attemptID: attemptID,
                result: current.match,
                humanReview: review
            )
            try await analysisRepository.save(record)
            let summary = AttemptSummaryV1(
                attempt: updated.capture.attempt,
                analysis: record,
                timezone: .current
            )
            try await summaryRepository.upsert(summary)
            if let index = allSummaries.firstIndex(where: { $0.attemptID == attemptID }) {
                allSummaries[index] = summary
            }
            if let index = visible.firstIndex(where: { $0.attemptID == attemptID }) {
                visible[index] = summary
            }
            reviewedCount = allSummaries.count { $0.humanOutcome != nil }
            feedbackExportURL = nil
            return updated
        } catch {
            loadError = error.localizedDescription
            return nil
        }
    }

    /// Builds the feedback dataset on demand. Only reviewed attempts load
    /// their raw payloads; the export is no longer rebuilt on every refresh.
    func prepareFeedbackExport() async {
        guard !isExportingFeedback else { return }
        isExportingFeedback = true
        feedbackExportError = nil
        defer { isExportingFeedback = false }
        do {
            var reviewed: [NativeRunResult] = []
            for summary in allSummaries where summary.humanOutcome != nil {
                let capture = try await attemptRepository.load(id: summary.attemptID)
                guard let analysis = try await analysisRepository.load(attemptID: summary.attemptID),
                      analysis.humanReview != nil else { continue }
                reviewed.append(NativeRunResult(
                    capture: capture,
                    match: analysis.result,
                    humanReview: analysis.humanReview
                ))
            }
            feedbackExportURL = try PlayerFeedbackExporter.export(
                results: reviewed,
                rootDirectory: rootDirectory
            )
            if feedbackExportURL == nil {
                feedbackExportError = "No reviewed attempts to export yet."
            }
        } catch {
            feedbackExportError = error.localizedDescription
        }
    }
}
