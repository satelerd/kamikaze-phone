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

    private(set) var recent: [NativeRunResult] = []
    private(set) var loadError: String?
    private(set) var isLoading = false

    init(rootDirectory: URL = AttemptStorageLocation.applicationRoot()) {
        attemptRepository = FileAttemptRepository(rootDirectory: rootDirectory)
        analysisRepository = FileAttemptAnalysisRepository(rootDirectory: rootDirectory)
    }

    var landedCount: Int {
        recent.count { $0.match.status == .recognized }
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
                let result = stored?.result ?? analyzeCurrent(capture)
                loaded.append(NativeRunResult(capture: capture, match: result))
            }
            recent = loaded
            loadError = nil
        } catch {
            loadError = error.localizedDescription
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
