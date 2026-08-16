import KamikazeMotionCore
import SwiftUI

/// G3 statistics surfaces: progressive disclosure over the deterministic
/// stats engine. Score-based records stay hidden until Game Score v1 exists.
struct StatsView: View {
    @Bindable var model: ProfileModel

    private enum Section: String, CaseIterable, Identifiable {
        case overview = "OVERVIEW"
        case tricks = "TRICKS"
        case records = "RECORDS"

        var id: String { rawValue }
    }

    @State private var section = Section.overview
    @State private var selectedAttempt: NativeRunResult?

    private var engine: PlayerStatsEngine {
        PlayerStatsEngine(summaries: model.allSummaries)
    }

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.volt)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("WHAT YOU\nACTUALLY LANDED.")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-1.5)

                    HStack(spacing: 8) {
                        ForEach(Section.allCases) { candidate in
                            Button {
                                section = candidate
                            } label: {
                                Text(candidate.rawValue)
                                    .font(.system(size: 10, weight: .black, design: .monospaced))
                                    .foregroundStyle(section == candidate ? Color.black : KamikazeTheme.frost)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 34)
                                    .background(
                                        section == candidate ? KamikazeTheme.volt : Color.white.opacity(0.08),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    switch section {
                    case .overview: overview
                    case .tricks: tricks
                    case .records: records
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedAttempt) { attempt in
            ResultReplayView(
                result: attempt,
                primaryTitle: "BACK TO STATS",
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
                }
            )
        }
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                statCell("\(engine.metrics.landedCount)", "LANDED")
                statCell("\(engine.metrics.attemptCount)", "ATTEMPTS")
                statCell("\(engine.metrics.currentStreak)", "CURRENT STREAK")
                statCell("\(engine.metrics.bestStreak)", "BEST STREAK")
            }
            GlassSurface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("ACTIVITY").font(.system(size: 10, weight: .bold, design: .monospaced))
                        Spacer()
                        Text("\(engine.activeDayCount) ACTIVE DAYS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                    if engine.metrics.landedCount == 0 {
                        Text("Confirm your first landing and this field starts filling in.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                    } else {
                        ActivityFieldView(engine: engine)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Tricks

    @ViewBuilder
    private var tricks: some View {
        if engine.trickStats.isEmpty {
            emptyCard("No recognized tricks yet", detail: "Land something in Play and it shows up here.")
        } else {
            GlassSurface {
                VStack(spacing: 12) {
                    ForEach(engine.trickStats) { stat in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stat.trickID.displayName)
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                Text("\(stat.landedCount) LANDED / \(stat.attemptCount) ATTEMPTS")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(stat.bestFitPercent.map { "\($0) FIT" } ?? "—")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.volt)
                                Text(stat.fastestLandedMs.map { "\($0) MS BEST" } ?? "NOT LANDED")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                            }
                        }
                        if stat.id != engine.trickStats.last?.id {
                            Divider().overlay(.white.opacity(0.08))
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Records

    @ViewBuilder
    private var records: some View {
        if engine.fastestLanded == nil && engine.bestFit == nil {
            emptyCard("No records yet", detail: "Records come from confirmed landings and recognized throws.")
        } else {
            VStack(spacing: 10) {
                recordCard("FASTEST LANDED", record: engine.fastestLanded)
                recordCard("LONGEST LANDED", record: engine.longestLanded)
                recordCard("BEST FIT", record: engine.bestFit)
                Text("Motion duration, not airtime. Score records unlock with Game Score v1.")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
            }
        }
    }

    @ViewBuilder
    private func recordCard(_ title: String, record: PlayerStatsEngine.Record?) -> some View {
        if let record {
            Button {
                Task {
                    if let result = await model.openAttempt(id: record.attemptID) {
                        selectedAttempt = result
                    }
                }
            } label: {
                GlassSurface(role: .interactiveCard) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.muted)
                            Text(record.trickID?.displayName ?? "UNKNOWN")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                        }
                        Spacer()
                        Text(record.valueLabel)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundStyle(KamikazeTheme.volt)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                    .padding(16)
                }
            }
            .buttonStyle(.plain)
            .disabled(model.isOpeningAttempt)
        }
    }

    private func emptyCard(_ title: String, detail: String) -> some View {
        GlassSurface {
            ContentUnavailableView(title, systemImage: "chart.bar", description: Text(detail))
                .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        GlassSurface {
            VStack(alignment: .leading, spacing: 5) {
                Text(value).font(.system(size: 25, weight: .black, design: .rounded))
                Text(label).font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(KamikazeTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}
