import Foundation
import KamikazeMotionCore
import Observation

@MainActor
@Observable
final class ProfileModel {
    private let attemptRepository: FileAttemptRepository
    private let analysisRepository: FileAttemptAnalysisRepository
    private let matcher = TrickMatcher()
    private let catalog = TrickCatalog.provisional(gripHand: .right)
    private let rootDirectory: URL

    private(set) var recent: [NativeRunResult] = []
    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var feedbackExportURL: URL?

    init(rootDirectory: URL = AttemptStorageLocation.applicationRoot()) {
        self.rootDirectory = rootDirectory
        attemptRepository = FileAttemptRepository(rootDirectory: rootDirectory)
        analysisRepository = FileAttemptAnalysisRepository(rootDirectory: rootDirectory)
    }

    var recognizedCount: Int {
        recent.count { $0.match.status == .recognized }
    }

    var confirmedLandedCount: Int {
        recent.count(where: \.hasConfirmedLanding)
    }

    var highFit: Int? {
        recent.filter { $0.match.status == .recognized }.map(\.fit).max()
    }

    var bestRun: Int {
        var best = 0
        var current = 0
        for attempt in recent.reversed() {
            if attempt.match.status == .recognized {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let metadata = try await attemptRepository.list()
            var loaded: [NativeRunResult] = []
            loaded.reserveCapacity(metadata.count)
            for attempt in metadata {
                let capture = try await attemptRepository.load(id: attempt.id)
                let stored = try await analysisRepository.load(attemptID: attempt.id)
                let result: TrickMatchResult
                if let stored,
                   stored.schemaVersion == AttemptAnalysisRecord.schemaVersion,
                   stored.result.policyVersion == TrickMatchingPolicy.provisionalVersion,
                   stored.result.catalogVersion == catalog.version {
                    result = stored.result
                } else {
                    result = analyzeCurrent(capture)
                    try await analysisRepository.save(AttemptAnalysisRecord(
                        attemptID: attempt.id,
                        result: result,
                        humanReview: stored?.humanReview
                    ))
                }
                loaded.append(NativeRunResult(
                    capture: capture,
                    match: result,
                    humanReview: stored?.humanReview
                ))
            }
            recent = loaded
            feedbackExportURL = try PlayerFeedbackExporter.export(
                results: loaded,
                rootDirectory: rootDirectory
            )
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func applyHumanReview(
        attemptID: String,
        review: HumanAttemptReview
    ) async -> NativeRunResult? {
        guard let index = recent.firstIndex(where: { $0.id == attemptID }) else { return nil }
        let current = recent[index]
        let updated = current.replacingHumanReview(review)
        do {
            try await analysisRepository.save(AttemptAnalysisRecord(
                attemptID: attemptID,
                result: current.match,
                humanReview: review
            ))
            recent[index] = updated
            feedbackExportURL = try PlayerFeedbackExporter.export(
                results: recent,
                rootDirectory: rootDirectory
            )
            return updated
        } catch {
            loadError = error.localizedDescription
            return nil
        }
    }

    private func analyzeCurrent(_ capture: MotionCaptureV3) -> TrickMatchResult {
        let trigger: AttemptSegmentationTrigger = capture.attempt.triggerMode == .freefall ? .freefall : .gyro
        let segmented = SegmentedAttemptV3(
            captureMode: capture.attempt.captureMode,
            trigger: trigger,
            boundaries: capture.attempt.boundaries,
            samples: capture.samplePayload.samples,
            timedOut: false
        )
        return matcher.match(attempt: segmented, catalog: catalog)
    }
}
