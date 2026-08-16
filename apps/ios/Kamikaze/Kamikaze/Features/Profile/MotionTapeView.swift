import KamikazeMotionCore
import SwiftUI

/// The Profile's signature element: a thin chronological strip of every saved
/// attempt. Each mark encodes the attempt's state and opens its replay. It is
/// drawn from recorded evidence — never a decorative chart.
struct MotionTapeView: View {
    /// The tape shows the trailing window of history; older marks live in
    /// History. Keeps the strip cheap at any archive size.
    static let markLimit = 180

    /// Newest-first, as the summary repository returns.
    let summaries: [AttemptSummaryV1]
    let onSelect: (String) -> Void

    private var chronological: [AttemptSummaryV1] {
        summaries.prefix(Self.markLimit).reversed()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MOTION TAPE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .center, spacing: 5) {
                        ForEach(chronological) { summary in
                            Button {
                                onSelect(summary.attemptID)
                            } label: {
                                Capsule()
                                    .fill(color(for: summary))
                                    .frame(width: 5, height: height(for: summary))
                            }
                            .buttonStyle(.plain)
                            .id(summary.attemptID)
                            .accessibilityLabel("\(summary.displayName), \(summary.outcomeLabel)")
                        }
                    }
                    .frame(height: 34)
                    .padding(.horizontal, 2)
                }
                .onAppear {
                    if let last = chronological.last {
                        proxy.scrollTo(last.attemptID, anchor: .trailing)
                    }
                }
            }
        }
    }

    private func color(for summary: AttemptSummaryV1) -> Color {
        switch summary.humanOutcome {
        case .landed: return KamikazeTheme.volt
        case .missed: return KamikazeTheme.hazard
        case .unclear, .noAttempt: return KamikazeTheme.muted
        case nil:
            return summary.recognitionStatus == .recognized
                ? KamikazeTheme.frost.opacity(0.75)
                : KamikazeTheme.muted.opacity(0.6)
        }
    }

    /// Landed marks stand taller; unresolved evidence stays quiet.
    private func height(for summary: AttemptSummaryV1) -> CGFloat {
        switch summary.humanOutcome {
        case .landed: 30
        case .missed: 20
        case .unclear, .noAttempt: 12
        case nil: summary.recognitionStatus == .recognized ? 24 : 14
        }
    }
}
