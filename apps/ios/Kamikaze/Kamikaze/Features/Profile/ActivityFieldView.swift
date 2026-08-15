import SwiftUI

/// The landed-activity calendar: one square per local day, four intensities.
/// Shared by the Profile home and the Stats overview.
struct ActivityFieldView: View {
    let engine: PlayerStatsEngine
    var weeks = 10
    var cellSize: CGFloat = 22

    var body: some View {
        let columns = activityColumns()
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 4) {
                    ForEach(week, id: \.self) { dayKey in
                        let count = engine.activity(onDayKey: dayKey)
                        RoundedRectangle(cornerRadius: cellSize * 0.14)
                            .fill(intensity(for: count))
                            .frame(width: cellSize, height: cellSize)
                            .accessibilityLabel("\(dayKey): \(count) landed")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func activityColumns() -> [[String]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        var days: [String] = []
        for offset in stride(from: weeks * 7 - 1, through: 0, by: -1) {
            if let date = calendar.date(byAdding: .day, value: -offset, to: today) {
                days.append(PlayerStatsEngine.dayKey(for: date, in: .current))
            }
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0 ..< min($0 + 7, days.count)]) }
    }

    private func intensity(for count: Int) -> Color {
        switch count {
        case 0: Color.white.opacity(0.06)
        case 1: KamikazeTheme.volt.opacity(0.30)
        case 2 ... 3: KamikazeTheme.volt.opacity(0.60)
        default: KamikazeTheme.volt
        }
    }
}
