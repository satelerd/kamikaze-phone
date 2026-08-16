import Foundation
import KamikazeMotionCore

nonisolated struct PlayerFeedbackCaptureV1: Codable, Equatable, Sendable {
    let capture: MotionCaptureV3
    let machineResult: TrickMatchResult
    let humanReview: HumanAttemptReview
}

nonisolated struct PlayerFeedbackDatasetV1: Codable, Equatable, Sendable {
    let format: String
    let exportedAtISO8601: String
    let classificationRule: String
    let captures: [PlayerFeedbackCaptureV1]

    init(captures: [PlayerFeedbackCaptureV1], exportedAt: Date = Date()) {
        self.format = "kamikaze.player-feedback.v1"
        self.exportedAtISO8601 = ISO8601DateFormatter().string(from: exportedAt)
        self.classificationRule = "human-review-is-ground-truth; machine-result-is-observation-only"
        self.captures = captures
    }
}

@MainActor
enum PlayerFeedbackExporter {
    static func export(
        results: [NativeRunResult],
        rootDirectory: URL
    ) throws -> URL? {
        let reviewed = results.compactMap { result -> PlayerFeedbackCaptureV1? in
            guard let review = result.humanReview else { return nil }
            return PlayerFeedbackCaptureV1(
                capture: result.capture,
                machineResult: result.match,
                humanReview: review
            )
        }
        guard !reviewed.isEmpty else { return nil }

        let dataset = PlayerFeedbackDatasetV1(captures: reviewed)
        let data = try CapturePersistenceCodec.encode(dataset)
        // Validate the exact bytes that ShareLink will expose.
        let decoded = try CapturePersistenceCodec.decode(PlayerFeedbackDatasetV1.self, from: data)
        guard decoded == dataset else {
            throw AttemptPersistenceError.invalidCapture("Feedback export did not round-trip.")
        }
        let destination = rootDirectory
            .appending(path: "exports")
            .appending(path: "kamikaze-player-feedback-v1.json")
        try AtomicFileWriter.write(data, to: destination)
        return destination
    }
}
