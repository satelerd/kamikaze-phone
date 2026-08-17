import Foundation
import KamikazeMotionCore

nonisolated enum PlayMode: String, CaseIterable, Identifiable {
    case free
    case follow
    case classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "FREE"
        case .follow: "FOLLOW"
        case .classic: "CLASSIC"
        }
    }
}

nonisolated enum FollowCondition: String, CaseIterable, Sendable {
    case natural
    case fastLow
    case high
    case deliberateMiss

    var title: String {
        switch self {
        case .natural: "NATURAL"
        case .fastLow: "FAST + LOW"
        case .high: "HIGHER THROW"
        case .deliberateMiss: "INTENTIONAL MISS"
        }
    }

    var instruction: String {
        switch self {
        case .natural: "Use your normal height and rhythm."
        case .fastLow: "Keep it low and make the rotation quick."
        case .high: "Give it more air without changing the intended axes."
        case .deliberateMiss: "Attempt the trick, but intentionally under-rotate or use the wrong axis."
        }
    }
}

nonisolated struct FollowPrompt: Identifiable, Equatable, Sendable {
    let trickID: BuiltInTrickID
    let condition: FollowCondition

    var id: String { "\(trickID.rawValue)-\(condition.rawValue)" }
    var evidenceNote: String {
        "follow-v1;prompt=\(trickID.rawValue);condition=\(condition.rawValue)"
    }
}

nonisolated enum FollowPromptDeck {
    /// Human review, not detector confidence, is ground truth. Therefore the
    /// deck intentionally includes collection-only doubles and 180° Shuvits.
    static let tricks: [BuiltInTrickID] = [
        .flip, .reverseFlip,
        .phoneFlip, .reversePhoneFlip,
        .backsideShuvit, .frontsideShuvit,
        .backsideThreeSixtyShuvit, .frontsideThreeSixtyShuvit,
        .doubleFlip, .doubleReverseFlip,
        .doublePhoneFlip, .doubleReversePhoneFlip,
    ]

    static let prompts: [FollowPrompt] = tricks.flatMap { trick in
        FollowCondition.allCases.map { FollowPrompt(trickID: trick, condition: $0) }
    }

    static let first = FollowPrompt(trickID: .phoneFlip, condition: .natural)

    static func shuffled(avoiding current: FollowPrompt? = nil) -> [FollowPrompt] {
        var result = prompts.shuffled()
        if let current, result.first == current, result.count > 1 {
            result.swapAt(0, 1)
        }
        return result
    }
}
