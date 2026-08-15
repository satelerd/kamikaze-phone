import KamikazeMotionCore
import SwiftUI

/// Full attempt history over the lightweight summary index. Filtering and
/// sorting never decode raw payloads; opening one attempt loads its evidence
/// into the same detail used by Play's result.
struct HistoryView: View {
    @Bindable var model: ProfileModel

    private enum OutcomeFilter: String, CaseIterable, Identifiable {
        case all = "ALL"
        case landed = "LANDED"
        case missed = "MISSED"
        case unresolved = "UNRESOLVED"

        var id: String { rawValue }

        func matches(_ summary: AttemptSummaryV1) -> Bool {
            switch self {
            case .all: true
            case .landed: summary.humanOutcome == .landed
            case .missed: summary.humanOutcome == .missed
            case .unresolved: summary.humanOutcome == nil || summary.humanOutcome == .unclear
            }
        }
    }

    private enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "NEWEST"
        case oldest = "OLDEST"
        case bestFit = "BEST FIT"
        case fastest = "FASTEST"
        case longest = "LONGEST"

        var id: String { rawValue }

        func apply(_ summaries: [AttemptSummaryV1]) -> [AttemptSummaryV1] {
            switch self {
            case .newest: summaries
            case .oldest: summaries.reversed()
            case .bestFit: summaries.sorted { ($0.fit ?? -1) > ($1.fit ?? -1) }
            case .fastest: summaries.sorted { $0.motionDurationMs < $1.motionDurationMs }
            case .longest: summaries.sorted { $0.motionDurationMs > $1.motionDurationMs }
            }
        }
    }

    @State private var outcomeFilter = OutcomeFilter.all
    @State private var trickFilter: BuiltInTrickID?
    @State private var sortOrder = SortOrder.newest
    @State private var visibleLimit = 30
    @State private var selectedAttempt: NativeRunResult?

    private var availableTricks: [BuiltInTrickID] {
        var seen = Set<BuiltInTrickID>()
        return model.allSummaries.compactMap { summary in
            guard let trick = summary.trickID, seen.insert(trick).inserted else { return nil }
            return trick
        }
    }

    private var filtered: [AttemptSummaryV1] {
        let byOutcome = model.allSummaries.filter { outcomeFilter.matches($0) }
        let byTrick = trickFilter.map { trick in byOutcome.filter { $0.trickID == trick } } ?? byOutcome
        return sortOrder.apply(byTrick)
    }

    var body: some View {
        ZStack {
            KineticBackground(accent: KamikazeTheme.ion)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    SectionKicker(text: "HISTORY / \(filtered.count) OF \(model.totalCount)")
                    Text("EVERY THROW,\nON RECORD.")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-1.5)

                    filterBar

                    GlassSurface {
                        VStack(alignment: .leading, spacing: 12) {
                            if filtered.isEmpty {
                                ContentUnavailableView(
                                    "Nothing matches",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text("Change the filters to see more attempts.")
                                )
                                .frame(maxWidth: .infinity, minHeight: 160)
                            } else {
                                ForEach(filtered.prefix(visibleLimit)) { summary in
                                    Button {
                                        Task {
                                            if let result = await model.openAttempt(id: summary.attemptID) {
                                                selectedAttempt = result
                                            }
                                        }
                                    } label: {
                                        HistoryRow(summary: summary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(model.isOpeningAttempt)
                                    if summary.id != filtered.prefix(visibleLimit).last?.id {
                                        Divider()
                                    }
                                }
                                if filtered.count > visibleLimit {
                                    Button {
                                        visibleLimit += 30
                                    } label: {
                                        Text("SHOW MORE  ·  \(filtered.count - visibleLimit) LEFT")
                                            .font(.system(size: 11, weight: .black, design: .monospaced))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(KamikazeTheme.volt)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedAttempt) { attempt in
            ResultReplayView(
                result: attempt,
                primaryTitle: "BACK TO HISTORY",
                onAgain: { selectedAttempt = nil },
                onClose: { selectedAttempt = nil },
                onReview: { review in
                    guard let updated = await model.applyHumanReview(
                        attemptID: attempt.id,
                        review: review,
                        current: attempt
                    ) else { return nil }
                    selectedAttempt = updated
                    return updated
                },
                onDelete: {
                    if await model.deleteAttempt(id: attempt.id) {
                        selectedAttempt = nil
                    }
                }
            )
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(SortOrder.allCases) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                } label: {
                    chip(label: "SORT: \(sortOrder.rawValue)", active: sortOrder != .newest)
                }
                ForEach(OutcomeFilter.allCases) { filter in
                    Button {
                        outcomeFilter = filter
                        visibleLimit = 30
                    } label: {
                        chip(label: filter.rawValue, active: outcomeFilter == filter)
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    Picker("Trick", selection: $trickFilter) {
                        Text("ALL TRICKS").tag(BuiltInTrickID?.none)
                        ForEach(availableTricks, id: \.self) { trick in
                            Text(trick.displayName).tag(BuiltInTrickID?.some(trick))
                        }
                    }
                } label: {
                    chip(label: trickFilter?.displayName ?? "TRICK", active: trickFilter != nil)
                }
            }
        }
    }

    private func chip(label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(active ? Color.black : KamikazeTheme.frost)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(
                active ? KamikazeTheme.volt : Color.white.opacity(0.08),
                in: Capsule()
            )
    }
}

private struct HistoryRow: View {
    let summary: AttemptSummaryV1

    var body: some View {
        HStack(spacing: 14) {
            Text(summary.fit.map { String(Int(($0 * 100).rounded())) } ?? "—")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(summary.isRecognized ? KamikazeTheme.volt : KamikazeTheme.hazard)
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.displayName)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                Text("\(Int(summary.motionDurationMs.rounded())) MS  ·  \(summary.outcomeLabel)  ·  \(dayLabel)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(KamikazeTheme.muted)
        }
        .contentShape(Rectangle())
    }

    private var dayLabel: String {
        guard let date = ISO8601DateFormatter().date(from: summary.recordedAtISO8601) else {
            return "—"
        }
        return date.formatted(.dateTime.day().month(.abbreviated)).uppercased()
    }
}
