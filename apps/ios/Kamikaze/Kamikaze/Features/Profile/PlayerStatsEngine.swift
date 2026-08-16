import Foundation
import KamikazeMotionCore

/// Deterministic statistics over attempt summaries — the G3 engine from
/// PROFILE_LOCKER_STATS_V1. Same inputs always produce the same numbers, and
/// nothing here decodes raw motion payloads. Game Score and identity FIT stay
/// separate records.
nonisolated struct PlayerStatsEngine: Equatable, Sendable {
    struct TrickStat: Equatable, Sendable, Identifiable {
        let trickID: BuiltInTrickID
        /// Attempts whose displayed identity is this trick (noAttempt excluded).
        let attemptCount: Int
        /// Successes under the display rule (`countsAsSuccess`).
        let successCount: Int
        /// Best identity FIT among recognized attempts, display percent.
        let bestFitPercent: Int?
        /// Best deterministic gameplay score for this trick.
        let bestScore: Int?
        /// Fastest successful motion, in milliseconds.
        let fastestLandedMs: Int?
        /// Longest successful motion, in milliseconds.
        let longestLandedMs: Int?

        var id: BuiltInTrickID { trickID }
    }

    struct Record: Equatable, Sendable {
        let attemptID: String
        let trickID: BuiltInTrickID?
        let valueLabel: String
    }

    struct DayActivity: Equatable, Sendable, Identifiable {
        /// Stable local-calendar key, `yyyy-MM-dd`.
        let dayKey: String
        let successCount: Int

        var id: String { dayKey }
    }

    let metrics: PlayerMetrics
    let trickStats: [TrickStat]
    /// Success counts per local calendar day, most recent day first. A day
    /// belongs to the timezone stored with each summary; legacy summaries
    /// without one fall back to the provided default.
    let activity: [DayActivity]
    let fastestLanded: Record?
    let longestLanded: Record?
    let bestFit: Record?
    let bestScore: Record?
    let activeDayCount: Int

    init(summaries: [AttemptSummaryV1], defaultTimezone: TimeZone = .current) {
        metrics = PlayerMetrics(summaries: summaries)

        var byTrick: [BuiltInTrickID: [AttemptSummaryV1]] = [:]
        for summary in summaries where summary.humanOutcome != .noAttempt {
            guard let trickID = summary.trickID else { continue }
            byTrick[trickID, default: []].append(summary)
        }
        trickStats = byTrick
            .map { trickID, rows in
                let landed = rows.filter(\.countsAsSuccess)
                return TrickStat(
                    trickID: trickID,
                    attemptCount: rows.count,
                    successCount: landed.count,
                    bestFitPercent: rows
                        .filter(\.isRecognized)
                        .compactMap(\.fit)
                        .max()
                        .map { Int(($0 * 100).rounded()) },
                    bestScore: rows.compactMap(\.gameScore).max(),
                    fastestLandedMs: landed.map(\.motionDurationMs).min().map { Int($0.rounded()) },
                    longestLandedMs: landed.map(\.motionDurationMs).max().map { Int($0.rounded()) }
                )
            }
            .sorted { $0.attemptCount == $1.attemptCount ? $0.successCount > $1.successCount : $0.attemptCount > $1.attemptCount }

        let landed = summaries.filter(\.countsAsSuccess)
        fastestLanded = landed
            .min { $0.motionDurationMs < $1.motionDurationMs }
            .map { Record(attemptID: $0.attemptID, trickID: $0.trickID, valueLabel: "\(Int($0.motionDurationMs.rounded())) MS") }
        longestLanded = landed
            .max { $0.motionDurationMs < $1.motionDurationMs }
            .map { Record(attemptID: $0.attemptID, trickID: $0.trickID, valueLabel: "\(Int($0.motionDurationMs.rounded())) MS") }
        bestFit = summaries
            .filter { $0.isRecognized && $0.fit != nil }
            .max { ($0.fit ?? 0) < ($1.fit ?? 0) }
            .map { Record(attemptID: $0.attemptID, trickID: $0.trickID, valueLabel: "\(Int((($0.fit ?? 0) * 100).rounded())) FIT") }
        bestScore = summaries
            .filter { $0.gameScore != nil }
            .max { ($0.gameScore ?? 0) < ($1.gameScore ?? 0) }
            .map { Record(attemptID: $0.attemptID, trickID: $0.trickID, valueLabel: "\($0.gameScore ?? 0) PTS") }

        var byDay: [String: Int] = [:]
        let parser = ISO8601DateFormatter()
        for summary in landed {
            guard let date = parser.date(from: summary.recordedAtISO8601) else { continue }
            let timezone = summary.timezoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? defaultTimezone
            byDay[Self.dayKey(for: date, in: timezone), default: 0] += 1
        }
        activity = byDay
            .map { DayActivity(dayKey: $0.key, successCount: $0.value) }
            .sorted { $0.dayKey > $1.dayKey }
        activeDayCount = byDay.count
    }

    func activity(onDayKey key: String) -> Int {
        activity.first { $0.dayKey == key }?.successCount ?? 0
    }

    static func dayKey(for date: Date, in timezone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
