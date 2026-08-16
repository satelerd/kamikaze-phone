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

    /// Successful throws as the player sees them: human-confirmed landings
    /// plus unreviewed detector-recognized attempts (`countsAsSuccess`).
    /// Supersedes the v1 "human-confirmed only" rule by design decision.
    var successCount: Int {
        summaries.count(where: \.countsAsSuccess)
    }

    var reviewedCount: Int {
        summaries.count { $0.humanOutcome != nil }
    }

    /// Consecutive successes ending at the most recent attempt. Same
    /// success rule as `successCount`; a miss — confirmed by a human or an
    /// unreviewed unrecognized throw — breaks the streak. `unclear` and
    /// `noAttempt` are neutral.
    var currentStreak: Int {
        var streak = 0
        for summary in summaries {
            switch summary.humanOutcome {
            case .unclear, .noAttempt:
                continue
            case .landed, .missed, nil:
                if summary.countsAsSuccess {
                    streak += 1
                } else {
                    return streak
                }
            }
        }
        return streak
    }

    /// Longest success run across history, same rules as `currentStreak`.
    var bestStreak: Int {
        var best = 0
        var current = 0
        for summary in summaries.reversed() {
            switch summary.humanOutcome {
            case .unclear, .noAttempt:
                continue
            case .landed, .missed, nil:
                if summary.countsAsSuccess {
                    current += 1
                    best = max(best, current)
                } else {
                    current = 0
                }
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
