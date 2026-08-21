import SwiftUI

/// Compact, non-gamified social summary for the future Profile/Me surface.
/// It reports relationships and shared results without turning attention into
/// a score, streak, reward or leaderboard.
struct SocialProfileSummaryView: View {
    let summary: SocialProfileSummary
    let onOpenFeed: () -> Void

    init(summary: SocialProfileSummary, onOpenFeed: @escaping () -> Void = {}) {
        self.summary = summary
        self.onOpenFeed = onOpenFeed
    }

    var body: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    SocialAvatarView(user: summary.profile, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SOCIAL PRESENCE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.volt)
                        Text(summary.profile.displayName)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                        Text("@\(summary.profile.handle)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 0) {
                    SocialSummaryMetric(value: summary.followingCount, label: "FOLLOWING")
                    SocialSummaryMetric(value: summary.followerCount, label: "FOLLOWERS")
                    SocialSummaryMetric(value: summary.friendsCount, label: "FRIENDS")
                    SocialSummaryMetric(value: summary.publishedCount, label: "PUBLISHED")
                }

                Divider().overlay(.white.opacity(0.09))

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: summary.defaultAudience.iconName)
                        .foregroundStyle(KamikazeTheme.ion)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DEFAULT AUDIENCE  ·  \(summary.defaultAudience.title)")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                        Text("Every post still asks before it leaves this phone. A default never grants sensor or video upload consent.")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                }

                Button(action: onOpenFeed) {
                    Label("OPEN FOLLOWING + DISCOVER", systemImage: "person.2.wave.2")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .adaptiveGlassButton(tint: KamikazeTheme.ion)
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(summaryAccessibilityLabel)
    }

    private var summaryAccessibilityLabel: String {
        "Social presence for \(summary.profile.displayName). \(summary.followingCount) following, \(summary.followerCount) followers, \(summary.friendsCount) friends, \(summary.publishedCount) published results. Default audience \(summary.defaultAudience.title.lowercased())."
    }
}

private struct SocialSummaryMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(KamikazeTheme.frost)
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Loads the summary through the same repository boundary as the feed. This
/// wrapper is convenient for Profile integration while keeping the existing
/// Profile model untouched.
struct SocialProfileSummaryLoaderView: View {
    let repository: any SocialRepository
    let onOpenFeed: () -> Void
    @State private var summary: SocialProfileSummary?
    @State private var errorMessage: String?

    init(
        repository: any SocialRepository = MockSocialRepository(),
        onOpenFeed: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.onOpenFeed = onOpenFeed
    }

    var body: some View {
        Group {
            if let summary {
                SocialProfileSummaryView(summary: summary, onOpenFeed: onOpenFeed)
            } else if let errorMessage {
                SocialFeedEmptyState(title: "SOCIAL OFFLINE", detail: errorMessage, actionTitle: "RETRY") {
                    Task { await load() }
                }
            } else {
                ProgressView()
                    .tint(KamikazeTheme.volt)
                    .frame(maxWidth: .infinity, minHeight: 130)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            summary = try await repository.fetchProfileSummary()
        } catch {
            if let socialError = error as? SocialRepositoryError {
                errorMessage = socialError.message
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
