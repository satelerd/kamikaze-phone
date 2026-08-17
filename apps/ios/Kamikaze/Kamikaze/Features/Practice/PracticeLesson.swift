import Foundation

/// The player-facing lesson state. Capture remains owned by `NativeRunModel`;
/// this state machine only decides what Practice teaches and shows around it.
nonisolated enum PracticeLessonStep: Int, CaseIterable, Equatable, Sendable {
    case learn
    case follow
    case tryIt
    case review

    var label: String {
        switch self {
        case .learn: "LEARN"
        case .follow: "FOLLOW"
        case .tryIt: "TRY"
        case .review: "REVIEW"
        }
    }

    var next: PracticeLessonStep? {
        Self(rawValue: rawValue + 1)
    }

    func isComplete(relativeTo current: PracticeLessonStep) -> Bool {
        rawValue < current.rawValue
    }
}
