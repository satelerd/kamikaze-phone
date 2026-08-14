import CryptoKit
import Foundation
import KamikazeMotionCore

private struct Dataset: Decodable {
    let format: String
    let captures: [LabelledCapture]
}

private struct LabelledCapture: Decodable {
    let boundarySemantics: String
    let label: Label
    let capture: MotionCaptureV3
}

private struct Label: Decodable {
    let expectedTrickID: String
    let condition: String
    let outcome: String
}

private struct EvaluationSplit: Decodable {
    let sourceSHA256: String
    let development: [String]
    let holdout: [String]
}

private enum RequestedSplit: String {
    case development
    case holdout
    case all
}

@main
private enum MotionEvaluationCommand {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 5,
              arguments[1] == "--dataset",
              arguments[3] == "--split-manifest" else {
            throw EvaluationError.usage
        }

        let requested = value(after: "--set", in: arguments)
            .flatMap(RequestedSplit.init(rawValue:)) ?? .all
        let datasetURL = URL(fileURLWithPath: arguments[2])
        let splitURL = URL(fileURLWithPath: arguments[4])
        let datasetData = try Data(contentsOf: datasetURL)
        let dataset = try JSONDecoder().decode(Dataset.self, from: datasetData)
        let split = try JSONDecoder().decode(EvaluationSplit.self, from: Data(contentsOf: splitURL))
        try validate(dataset: dataset, bytes: datasetData, expectedSHA256: split.sourceSHA256)
        let selectedIDs: Set<String>
        switch requested {
        case .development: selectedIDs = Set(split.development)
        case .holdout: selectedIDs = Set(split.holdout)
        case .all: selectedIDs = Set(split.development + split.holdout)
        }

        let selected = dataset.captures.filter {
            selectedIDs.contains($0.capture.attempt.id)
        }
        guard selected.count == selectedIDs.count else {
            throw EvaluationError.missingCaptureIDs(selectedIDs.count - selected.count)
        }

        let matcher = TrickMatcher()
        let catalog = TrickCatalog.provisional(gripHand: .right)
        var landedCount = 0
        var landedCorrect = 0
        var missedCount = 0
        var missedAbstained = 0
        var confusion: [String: Int] = [:]

        print("dataset_sha256\t\(split.sourceSHA256)")
        print("set\t\(requested.rawValue)\tcaptures\t\(selected.count)")
        print("id\toutcome\texpected\tstatus\tpredicted\tfit\tmargin\tpurity\tstability\tcondition")

        for item in selected.sorted(by: recordedBefore) {
            let attempt = segmentedAttempt(from: item.capture)
            let result = matcher.match(attempt: attempt, catalog: catalog)
            let predicted = result.candidates.first?.definition.id.rawValue ?? "unknown"
            let fit = result.candidates.first?.presentationFit ?? 0
            let secondFit = result.candidates.dropFirst().first?.presentationFit ?? 0
            let margin = fit - secondFit
            let purity = result.features?.dominantAxisPurity ?? 0
            let stability = result.features?.postCatchStability ?? 0
            print([
                item.capture.attempt.id,
                item.label.outcome,
                item.label.expectedTrickID,
                result.status.rawValue,
                predicted,
                String(format: "%.3f", fit),
                String(format: "%.3f", margin),
                String(format: "%.3f", purity),
                String(format: "%.3f", stability),
                item.label.condition,
            ].joined(separator: "\t"))

            if item.label.outcome == "landed" {
                landedCount += 1
                let normalizedPrediction = normalizedID(predicted)
                if result.status == .recognized,
                   normalizedPrediction == item.label.expectedTrickID {
                    landedCorrect += 1
                }
                confusion["\(item.label.expectedTrickID)->\(normalizedPrediction)", default: 0] += 1
            } else if item.label.outcome == "missed" {
                missedCount += 1
                if result.status != .recognized { missedAbstained += 1 }
            }
        }

        print("summary\tlanded_correct\t\(landedCorrect)/\(landedCount)")
        print("summary\tmissed_abstained\t\(missedAbstained)/\(missedCount)")
        for (pair, count) in confusion.sorted(by: { $0.key < $1.key }) {
            print("confusion\t\(pair)\t\(count)")
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func validate(
        dataset: Dataset,
        bytes: Data,
        expectedSHA256: String
    ) throws {
        guard dataset.format == "kamikaze.labelled-motion-dataset.v1" else {
            throw EvaluationError.invalidDataset("Unexpected dataset format: \(dataset.format)")
        }
        let actualSHA256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard actualSHA256 == expectedSHA256 else {
            throw EvaluationError.sourceChecksumMismatch(expected: expectedSHA256, actual: actualSHA256)
        }
        let ids = dataset.captures.map(\.capture.attempt.id)
        guard Set(ids).count == ids.count else {
            throw EvaluationError.invalidDataset("Duplicate capture IDs.")
        }
        for item in dataset.captures {
            let capture = item.capture
            let reference = capture.attempt.rawSamples
            guard capture.attempt.id == capture.samplePayload.attemptID else {
                throw EvaluationError.invalidCapture(capture.attempt.id, "payload attempt ID mismatch")
            }
            guard reference.sampleCount == capture.samplePayload.samples.count else {
                throw EvaluationError.invalidCapture(capture.attempt.id, "sample count mismatch")
            }
            guard reference.payloadSchemaVersion == capture.samplePayload.schemaVersion else {
                throw EvaluationError.invalidCapture(capture.attempt.id, "payload schema mismatch")
            }
            let payloadData = try canonicalJSON(capture.samplePayload)
            let payloadSHA256 = SHA256.hash(data: payloadData).map { String(format: "%02x", $0) }.joined()
            guard payloadSHA256 == reference.checksum else {
                throw EvaluationError.invalidCapture(capture.attempt.id, "raw payload checksum mismatch")
            }
        }
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func segmentedAttempt(from capture: MotionCaptureV3) -> SegmentedAttemptV3 {
        let trigger: AttemptSegmentationTrigger
        switch capture.attempt.triggerMode {
        case .freefall: trigger = .freefall
        case .gyro: trigger = .gyro
        case nil: trigger = .manual
        }
        return SegmentedAttemptV3(
            captureMode: capture.attempt.captureMode,
            trigger: trigger,
            boundaries: capture.attempt.boundaries,
            samples: capture.samplePayload.samples,
            timedOut: false
        )
    }

    private static func normalizedID(_ id: String) -> String {
        switch id {
        case "front-flip": return "flip"
        case "back-flip": return "reverse-flip"
        default: return id
        }
    }

    private static func recordedBefore(_ lhs: LabelledCapture, _ rhs: LabelledCapture) -> Bool {
        lhs.capture.attempt.recordedAtISO8601 < rhs.capture.attempt.recordedAtISO8601
    }

    private enum EvaluationError: Error, CustomStringConvertible {
        case usage
        case missingCaptureIDs(Int)
        case invalidDataset(String)
        case invalidCapture(String, String)
        case sourceChecksumMismatch(expected: String, actual: String)

        var description: String {
            switch self {
            case .usage:
                return "Usage: kamikaze-motion-eval --dataset <json> --split-manifest <json> [--set development|holdout|all]"
            case let .missingCaptureIDs(count):
                return "Dataset is missing \(count) capture IDs declared by the split manifest."
            case let .invalidDataset(reason):
                return "Invalid dataset: \(reason)"
            case let .invalidCapture(id, reason):
                return "Invalid capture \(id): \(reason)."
            case let .sourceChecksumMismatch(expected, actual):
                return "Dataset SHA-256 mismatch. Expected \(expected), got \(actual)."
            }
        }
    }
}
