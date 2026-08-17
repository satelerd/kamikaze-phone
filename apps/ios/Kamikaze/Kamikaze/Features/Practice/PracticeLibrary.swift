import Foundation
import KamikazeMotionCore

/// Trick readiness in the practice pipeline, mirroring
/// `docs/PRACTICE_PROGRESSION_V1.md`. Only `detectorReady` tricks may start a
/// scored practice run; everything else routes to the Trick Lab so the app
/// never pretends it can judge a motion it has no validated definition for.
nonisolated enum PracticeTrickReadiness: String, Equatable, Sendable {
    case collectingEvidence
    case candidateNeedsHoldout
    case detectorReady

    var label: String {
        switch self {
        case .collectingEvidence: "NEEDS DATA"
        case .candidateNeedsHoldout: "NEEDS HOLDOUT"
        case .detectorReady: "READY"
        }
    }
}

nonisolated struct PracticeTrickNode: Equatable, Sendable, Identifiable {
    let trickID: BuiltInTrickID
    let readiness: PracticeTrickReadiness
    /// One physical cue, not a manual.
    let coachingCue: String

    var id: BuiltInTrickID { trickID }
}

nonisolated struct PracticePair: Equatable, Sendable, Identifiable {
    let order: Int
    let title: String
    let primary: PracticeTrickNode
    let opposite: PracticeTrickNode

    var id: Int { order }
    var tricks: [PracticeTrickNode] { [primary, opposite] }
    var isDetectorReady: Bool {
        primary.readiness == .detectorReady && opposite.readiness == .detectorReady
    }
}

/// The deliberate skill ladder. Readiness reflects the physically validated
/// v0.2 matcher (2026-08-13/14 sessions): both 360 Shuvits, Flip/Reverse and
/// Phone Flip/Reverse are detector-ready; 180 Shuvits and every Double are
/// collection-only until their own sessions exist.
nonisolated enum PracticeLibrary {
    static let pairs: [PracticePair] = [
        PracticePair(
            order: 1,
            title: "SHUVIT",
            primary: PracticeTrickNode(
                trickID: .backsideShuvit,
                readiness: .collectingEvidence,
                coachingCue: "Half spin, screen stays up. Kill the flip axis."
            ),
            opposite: PracticeTrickNode(
                trickID: .frontsideShuvit,
                readiness: .collectingEvidence,
                coachingCue: "Same half spin, opposite direction."
            )
        ),
        PracticePair(
            order: 2,
            title: "FULL SHUVIT",
            primary: PracticeTrickNode(
                trickID: .backsideThreeSixtyShuvit,
                readiness: .detectorReady,
                coachingCue: "Full 360 spin around the screen axis. Flat catch."
            ),
            opposite: PracticeTrickNode(
                trickID: .frontsideThreeSixtyShuvit,
                readiness: .detectorReady,
                coachingCue: "Full spin the other way. Keep it level."
            )
        ),
        PracticePair(
            order: 3,
            title: "FLIP",
            primary: PracticeTrickNode(
                trickID: .flip,
                readiness: .detectorReady,
                coachingCue: "One clean flip over the long axis. Quiet spin."
            ),
            opposite: PracticeTrickNode(
                trickID: .reverseFlip,
                readiness: .detectorReady,
                coachingCue: "Flip it toward you instead. Same axis, reversed."
            )
        ),
        PracticePair(
            order: 4,
            title: "DOUBLE FLIP",
            primary: PracticeTrickNode(
                trickID: .doubleFlip,
                readiness: .collectingEvidence,
                coachingCue: "Two full flips. Snap harder, catch later."
            ),
            opposite: PracticeTrickNode(
                trickID: .doubleReverseFlip,
                readiness: .collectingEvidence,
                coachingCue: "Two flips toward you."
            )
        ),
        PracticePair(
            order: 5,
            title: "PHONE FLIP",
            primary: PracticeTrickNode(
                trickID: .phoneFlip,
                readiness: .detectorReady,
                coachingCue: "Flip plus spin together — the phone's 360 flip."
            ),
            opposite: PracticeTrickNode(
                trickID: .reversePhoneFlip,
                readiness: .detectorReady,
                coachingCue: "The compound motion, mirrored."
            )
        ),
        PracticePair(
            order: 6,
            title: "DOUBLE PHONE FLIP",
            primary: PracticeTrickNode(
                trickID: .doublePhoneFlip,
                // Two consistent landed examples seed a development
                // reference, but were used to derive it and cannot validate
                // it. Keep automatic recognition locked until a new session.
                readiness: .candidateNeedsHoldout,
                coachingCue: "Double everything. Height buys time."
            ),
            opposite: PracticeTrickNode(
                trickID: .doubleReversePhoneFlip,
                readiness: .collectingEvidence,
                coachingCue: "The double compound, mirrored."
            )
        ),
    ]

    static func pair(containing trickID: BuiltInTrickID) -> PracticePair? {
        pairs.first { $0.tricks.contains { $0.trickID == trickID } }
    }
}

/// Progression is derived from persisted attempt summaries — never from a
/// second completion flag. An exact detector-recognized identity counts
/// automatically; when a human verdict exists it supersedes the detector.
nonisolated struct PracticeProgress: Equatable, Sendable {
    static let repsToUnlock = 3
    static let masteryWindow = 5
    static let masteryReps = 3

    private let byTrick: [BuiltInTrickID: [AttemptSummaryV1]]

    /// - Parameter summaries: newest-first, as the summary repository returns.
    init(summaries: [AttemptSummaryV1]) {
        var grouped: [BuiltInTrickID: [AttemptSummaryV1]] = [:]
        for summary in summaries {
            guard let trickID = summary.trickID else { continue }
            grouped[trickID, default: []].append(summary)
        }
        byTrick = grouped
    }

    static func isQualifying(_ summary: AttemptSummaryV1, target: BuiltInTrickID) -> Bool {
        summary.trickID == target && summary.countsAsSuccess
    }

    func attemptCount(for trickID: BuiltInTrickID) -> Int {
        byTrick[trickID]?.count ?? 0
    }

    func qualifyingReps(for trickID: BuiltInTrickID) -> Int {
        byTrick[trickID]?.count { Self.isQualifying($0, target: trickID) } ?? 0
    }

    func isUnlockedByReps(_ trickID: BuiltInTrickID) -> Bool {
        qualifyingReps(for: trickID) >= Self.repsToUnlock
    }

    /// Mastery: at least 3 qualifying reps within the latest 5 attempts at
    /// this trick.
    func isMastered(_ trickID: BuiltInTrickID) -> Bool {
        guard let attempts = byTrick[trickID] else { return false }
        let window = attempts.prefix(Self.masteryWindow)
        return window.count { Self.isQualifying($0, target: trickID) } >= Self.masteryReps
    }

    func isPairMastered(_ pair: PracticePair) -> Bool {
        isMastered(pair.primary.trickID) && isMastered(pair.opposite.trickID)
    }

    /// A pair is playable when its tricks are detector-ready and every earlier
    /// detector-ready pair is mastered. Collection-only pairs never block the
    /// ladder — they cannot be judged yet, so they cannot gate progression.
    func isPairUnlocked(_ pair: PracticePair) -> Bool {
        guard pair.isDetectorReady else { return false }
        for earlier in PracticeLibrary.pairs where earlier.order < pair.order {
            if earlier.isDetectorReady, !isPairMastered(earlier) {
                return false
            }
        }
        return true
    }

    /// Within a pair, the regular direction unlocks first; its opposite opens
    /// after three qualifying reps (automatic or human-corrected captures).
    func isTrickUnlocked(_ trickID: BuiltInTrickID, in pair: PracticePair) -> Bool {
        guard isPairUnlocked(pair) else { return false }
        if trickID == pair.primary.trickID { return true }
        return isUnlockedByReps(pair.primary.trickID)
    }
}
