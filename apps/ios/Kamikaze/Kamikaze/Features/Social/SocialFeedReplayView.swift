import KamikazeMotionCore
import SwiftUI

/// Only the dominant feed card mounts RealityKit. Off-screen cards remain
/// lightweight static summaries, avoiding a stack of simultaneous 3D scenes.
struct SocialFeedReplayView: View {
    let post: SocialPost
    let isActive: Bool

    @State private var replay: ReplayController

    init(post: SocialPost, isActive: Bool) {
        self.post = post
        self.isActive = isActive
        _replay = State(initialValue: ReplayController(
            frames: Self.frames(for: post.result),
            clockMode: .continuous
        ))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ReplayPhoneScene(
                controller: replay,
                accent: accent
            )
            .frame(height: 280)

            HStack(spacing: 7) {
                Circle()
                    .fill(KamikazeTheme.volt)
                    .frame(width: 7, height: 7)
                Text("3D TRICK PREVIEW  ·  \(post.result.trickName)")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.frost)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.48), in: Capsule())
            .padding(12)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task(id: isActive) {
            replay.pause()
            replay.seek(toProgress: 0)
            guard isActive else { return }
            while !Task.isCancelled {
                replay.play()
                let cycleMs = max(900, replay.durationMs / replay.speed.rawValue + 320)
                try? await Task.sleep(for: .milliseconds(Int(cycleMs)))
                guard !Task.isCancelled else { return }
                replay.seek(toProgress: 0)
            }
        }
        .onDisappear { replay.pause() }
        .accessibilityLabel("Three dimensional replay of \(post.result.trickName)")
    }

    private var accent: Color {
        post.result.landed == false ? KamikazeTheme.hazard : KamikazeTheme.volt
    }

    private nonisolated static func frames(for result: SocialResultSnapshot) -> [ReplayFrame] {
        let catalog = TrickCatalog.provisional(gripHand: .right, includesUncalibratedCombos: true)
        let definition = catalog.definitions.first {
            $0.displayName.caseInsensitiveCompare(result.trickName) == .orderedSame
        } ?? catalog.definitions.first { $0.id == .straightAir }
        return definition.map { TargetMotionGenerator.frames(for: $0) } ?? []
    }
}

struct SocialPublicProfileView: View {
    let user: SocialUser
    let posts: [SocialPost]

    var body: some View {
        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        SocialAvatarView(user: user, size: 72)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .tracking(-1)
                            Text("@\(user.handle)")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.ion)
                            Text(user.isFollowedByViewer ? "FOLLOWING" : "DISCOVER")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.muted)
                        }
                    }

                    Text("\(posts.count) SHARED \(posts.count == 1 ? "THROW" : "THROWS")")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.volt)

                    ForEach(posts) { post in
                        PublishedResultCardView(
                            result: post.result,
                            compact: false,
                            attachments: post.attachments
                        )
                    }
                }
                .padding(20)
                .padding(.bottom, 80)
            }
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
