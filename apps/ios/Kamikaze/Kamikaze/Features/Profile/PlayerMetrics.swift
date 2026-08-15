import Foundation
import KamikazeMotionCore

/// Deterministic reductions over attempt summaries. Every number shown on
/// Profile derives from here so its definition is written (and tested) once.
/// This is the seed of `PlayerStatsEngine` from PROFILE_LOCKER_STATS_V1.
nonisolated struct PlayerMetrics: Equatable, Sendable {
    let summaries: [AttemptSummaryV1]

    /// - Parameter summaries: newest-first, as the summary repository returns.
    init(summaries: [AttemptSummaryV1]) {
        self.summaries = summaries
    }

    /// Closed valid captures, excluding human-labelled `noAttempt`.
    var attemptCount: Int {
        summaries.count { $0.humanOutcome != .noAttempt }
    }

    /// Detector-recognized identity or a valid human trick correction.
    var recognizedCount: Int {
        summaries.count(where: \.isRecognized)
    }

    /// Human-confirmed landings only. FIT never counts as landing in v1.
    var landedCount: Int {
        summaries.count(where: \.hasConfirmedLanding)
    }

    var reviewedCount: Int {
        summaries.count { $0.humanOutcome != nil }
    }

    /// Consecutive landed attempts ending at the most recent attempt:
    /// a confirmed miss breaks the streak, `noAttempt` is ignored, and an
    /// unreviewed or unclear attempt is neutral — it neither counts nor
    /// breaks (it is still waiting for review).
    var currentStreak: Int {
        var streak = 0
        for summary in summaries {
            switch summary.humanOutcome {
            case .landed:
                streak += 1
            case .missed:
                return streak
            case .unclear, .noAttempt, nil:
                continue
            }
        }
        return streak
    }

    /// Longest landed run across history, same neutrality rules as
    /// `currentStreak`.
    var bestStreak: Int {
        var best = 0
        var current = 0
        for summary in summaries.reversed() {
            switch summary.humanOutcome {
            case .landed:
                current += 1
                best = max(best, current)
            case .missed:
                current = 0
            case .unclear, .noAttempt, nil:
                continue
            }
        }
        return best
    }

    /// Highest identity FIT among recognized attempts, as a display percent.
    var highFitPercent: Int? {
        summaries
            .filter(\.isRecognized)
            .compactMap(\.fit)
            .max()
            .map { Int(($0 * 100).rounded()) }
    }
}
