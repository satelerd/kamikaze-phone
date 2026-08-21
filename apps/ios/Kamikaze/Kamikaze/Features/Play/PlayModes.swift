import Foundation
import KamikazeMotionCore

nonisolated enum PlayMode: String, CaseIterable, Identifiable {
    case free
    case line
    case follow
    case classic
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: "FREE"
        case .line: "LINE"
        case .follow: "FOLLOW"
        case .classic: "CLASSIC"
        case .camera: "CAMERA RUN"
        }
    }

    var symbol: String {
        switch self {
        case .free: "arrow.trianglehead.2.clockwise.rotate.90"
        case .line: "bolt.horizontal.circle"
        case .follow: "figure.run"
        case .classic: "arrow.up"
        case .camera: "video"
        }
    }

    var detail: String {
        switch self {
        case .free: "One throw, full result and replay."
        case .line: "Always listening. Stack tricks without leaving Play."
        case .follow: "Answer a randomized trick call."
        case .classic: "Height and airtime, like the original game."
        case .camera: "Record the performance before editing and sharing."
        }
    }
}

nonisolated struct LineTrickEvent: Identifiable, Equatable, Sendable {
    let id: String
    let trickName: String
    let points: Int
    let recognized: Bool

    init(id: String, trickName: String, points: Int, recognized: Bool) {
        self.id = id
        self.trickName = trickName
        self.points = max(0, points)
        self.recognized = recognized
    }
}

/// A LINE is a presentation aggregate only. Every throw is still persisted as
/// its own immutable attempt, so replay/history and future re-analysis retain
/// the exact same evidence contract as Free Play.
nonisolated struct LineSessionState: Equatable, Sendable {
    private(set) var events: [LineTrickEvent] = []

    var totalScore: Int { events.reduce(0) { $0 + $1.points } }
    var trickCount: Int { events.count { $0.recognized } }
    var attemptCount: Int { events.count }

    mutating func record(_ event: LineTrickEvent) {
        guard !events.contains(where: { $0.id == event.id }) else { return }
        events.append(event)
    }

    mutating func reset() {
        events.removeAll(keepingCapacity: true)
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
