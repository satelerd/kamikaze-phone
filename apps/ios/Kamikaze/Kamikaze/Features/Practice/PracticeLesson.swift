import Foundation
import KamikazeMotionCore

/// The player-facing lesson state. Capture remains owned by `NativeRunModel`;
/// this state machine only decides what Practice teaches and shows around it.
nonisolated enum PracticeLessonStep: Int, CaseIterable, Equatable, Sendable {
    case learn
    case tryIt

    var label: String {
        switch self {
        case .learn: "LEARN"
        case .tryIt: "TRY"
        }
    }

    var next: PracticeLessonStep? {
        Self(rawValue: rawValue + 1)
    }

    func isComplete(relativeTo current: PracticeLessonStep) -> Bool {
        rawValue < current.rawValue
    }
}

/// Practice is stricter than Play: recognizing *a* valid trick is not enough.
/// The automatic result only passes when its canonical identity is the exact
/// lesson target. A later player correction always supersedes the detector.
nonisolated enum PracticeAttemptJudgement {
    static func isSuccess(
        target: BuiltInTrickID,
        automaticStatus: TrickRecognitionStatus,
        automaticTrickID: BuiltInTrickID?,
        humanReview: HumanAttemptReview?
    ) -> Bool {
        if let humanReview {
            return humanReview.outcome == .landed && humanReview.trickID == target
        }
        return automaticStatus == .recognized && automaticTrickID == target
    }
}
