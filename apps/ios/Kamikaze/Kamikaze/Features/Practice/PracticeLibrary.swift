import Foundation
import KamikazeMotionCore

/// Trick readiness in the practice pipeline, mirroring
/// `docs/PRACTICE_PROGRESSION_V1.md`. Detector-ready and visibly-labelled beta
/// candidates may start a scored practice run; evidence-only tricks route to
/// Trick Lab so the app never pretends it can judge an unmodelled motion.
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

    /// Candidate definitions are intentionally playable in the beta so the
    /// rider can validate them in context. They stay visibly labelled BETA
    /// until a separate physical holdout session passes.
    var isPlayable: Bool {
        self != .collectingEvidence
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
    var playableTricks: [PracticeTrickNode] { tricks.filter { $0.readiness.isPlayable } }
    var isPracticePlayable: Bool { !playableTricks.isEmpty }
    var containsCandidate: Bool { tricks.contains { $0.readiness == .candidateNeedsHoldout } }
}

/// The single next skill Profile can point at. It is derived from the same
/// mastery window as Practice, so Profile never invents a separate XP track.
nonisolated struct PracticeGoal: Equatable, Sendable {
    let trickID: BuiltInTrickID
    let pairOrder: Int
    let cleanReps: Int
    let requiredReps: Int
}

/// The deliberate skill ladder. Readiness reflects the physically validated
/// v0.3 matcher: both 180 Shuvits and Double Flip now have V4-derived
/// candidate definitions. They are playable, but stay visibly marked BETA
/// until a new physical session validates them independently.
nonisolated enum PracticeLibrary {
    static let pairs: [PracticePair] = [
        PracticePair(
            order: 1,
            title: "SHUVIT",
            primary: PracticeTrickNode(
                trickID: .backsideShuvit,
                readiness: .candidateNeedsHoldout,
                coachingCue: "Half spin, screen stays up. Kill the flip axis."
            ),
            opposite: PracticeTrickNode(
                trickID: .frontsideShuvit,
                readiness: .candidateNeedsHoldout,
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
                readiness: .candidateNeedsHoldout,
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
                // Two landed examples are not enough to define and validate
                // this compound class. Keep collecting before making it a
                // playable candidate.
                readiness: .collectingEvidence,
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

    /// Clean reps inside the current mastery window. Unlike the lifetime
    /// qualifying total, this can fall after a run of misses and therefore is
    /// the truthful player-facing progress toward current mastery.
    func masteryReps(for trickID: BuiltInTrickID) -> Int {
        guard let attempts = byTrick[trickID] else { return 0 }
        return attempts.prefix(Self.masteryWindow)
            .count { Self.isQualifying($0, target: trickID) }
    }

    func isUnlockedByReps(_ trickID: BuiltInTrickID) -> Bool {
        qualifyingReps(for: trickID) >= Self.repsToUnlock
    }

    /// Mastery: at least 3 qualifying reps within the latest 5 attempts at
    /// this trick.
    func isMastered(_ trickID: BuiltInTrickID) -> Bool {
        masteryReps(for: trickID) >= Self.masteryReps
    }

    func isPairMastered(_ pair: PracticePair) -> Bool {
        let playable = pair.playableTricks
        return !playable.isEmpty && playable.allSatisfy { isMastered($0.trickID) }
    }

    /// A pair is playable when it contains at least one modelled trick and
    /// every earlier playable pair is mastered. Collection-only directions do
    /// not block a pair whose primary direction already has a candidate.
    func isPairUnlocked(_ pair: PracticePair) -> Bool {
        guard pair.isPracticePlayable else { return false }
        for earlier in PracticeLibrary.pairs where earlier.order < pair.order {
            if earlier.isPracticePlayable, !isPairMastered(earlier) {
                return false
            }
        }
        return true
    }

    /// Within a pair, the regular direction unlocks first; its opposite opens
    /// after three qualifying reps (automatic or human-corrected captures).
    func isTrickUnlocked(_ trickID: BuiltInTrickID, in pair: PracticePair) -> Bool {
        guard isPairUnlocked(pair) else { return false }
        guard let node = pair.tricks.first(where: { $0.trickID == trickID }),
              node.readiness.isPlayable else { return false }
        if trickID == pair.primary.trickID { return true }
        return isUnlockedByReps(pair.primary.trickID)
    }

    /// First unmastered playable skill in the authored ladder. Evidence-only
    /// nodes are skipped because Profile must point somewhere judgeable.
    func nextGoal() -> PracticeGoal? {
        for pair in PracticeLibrary.pairs where pair.isPracticePlayable {
            for node in pair.playableTricks where !isMastered(node.trickID) {
                return PracticeGoal(
                    trickID: node.trickID,
                    pairOrder: pair.order,
                    cleanReps: masteryReps(for: node.trickID),
                    requiredReps: Self.masteryReps
                )
            }
        }
        return nil
    }
}
