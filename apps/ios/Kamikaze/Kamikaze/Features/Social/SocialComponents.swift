import SwiftUI

// MARK: - Small visual vocabulary

private enum SocialVisuals {
    static func avatarAccent(seed: Int) -> Color {
        switch abs(seed) % 3 {
        case 0: KamikazeTheme.ion
        case 1: KamikazeTheme.hazard
        default: KamikazeTheme.volt
        }
    }

    static func resultAccent(for result: SocialResultSnapshot) -> Color {
        if result.landed == false { return KamikazeTheme.hazard }
        if result.landed == true { return KamikazeTheme.volt }
        return KamikazeTheme.ion
    }
}

struct SocialAvatarView: View {
    let user: SocialUser
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle()
                .fill(SocialVisuals.avatarAccent(seed: user.avatarSeed).opacity(0.20))
            Circle()
                .stroke(SocialVisuals.avatarAccent(seed: user.avatarSeed).opacity(0.65), lineWidth: 1)
            Text(user.initials)
                .font(.system(size: size * 0.28, weight: .black, design: .rounded))
                .foregroundStyle(KamikazeTheme.frost)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Profile picture for \(user.displayName)")
    }
}

struct SocialSectionLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted.opacity(0.8))
            }
        }
        .textCase(.uppercase)
    }
}

struct SocialPill: View {
    let title: String
    let systemImage: String
    var tint: Color = KamikazeTheme.ion

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10), in: Capsule(style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Audience and upload choices

struct SocialAudiencePicker: View {
    @Binding var selection: SocialAudience

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SocialSectionLabel(
                title: "WHO CAN SEE IT",
                detail: "Choose before publishing"
            )
            ForEach(SocialAudience.allCases) { audience in
                Button {
                    selection = audience
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: audience.iconName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(selection == audience ? KamikazeTheme.volt : KamikazeTheme.muted)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(audience.title)
                                .font(.system(size: 12, weight: .black, design: .rounded))
                            Text(audience.detail)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(KamikazeTheme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: selection == audience ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection == audience ? KamikazeTheme.volt : KamikazeTheme.muted)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audience.accessibilityLabel)
                .accessibilityValue(selection == audience ? "Selected" : "Not selected")
            }
        }
    }
}

struct SocialUploadConsentPanel: View {
    @Binding var includeReplayVideo: Bool
    @Binding var includeSensorEvidence: Bool
    @Binding var consentAccepted: Bool

    var body: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SocialSectionLabel(
                    title: "OPTIONAL UPLOADS",
                    detail: "Nothing uploads by default"
                )

                Toggle(isOn: $includeReplayVideo) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("REPLAY VIDEO")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                        Text("A rendered clip of this result.")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                }
                .tint(KamikazeTheme.ion)

                Divider().overlay(.white.opacity(0.08))

                Toggle(isOn: $includeSensorEvidence) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SENSOR EVIDENCE")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                        Text("Raw motion samples for review, not a public default.")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                }
                .tint(KamikazeTheme.hazard)

                if includeReplayVideo || includeSensorEvidence {
                    Divider().overlay(.white.opacity(0.08))
                    Toggle(isOn: $consentAccepted) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("I UNDERSTAND THESE FILES WILL BE SHARED")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                            Text("The selected files may reveal motion, timing and surroundings. This consent is recorded with this post.")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(KamikazeTheme.muted)
                        }
                    }
                    .tint(KamikazeTheme.volt)
                    .accessibilityHint("Required when a replay video or sensor evidence is attached.")
                } else {
                    Label("Result card only — no video or sensor data will be uploaded.", systemImage: "checkmark.shield")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.volt)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Published result card

struct PublishedResultCardView: View {
    let result: SocialResultSnapshot
    var compact: Bool = false
    var attachments: [SocialAttachment] = []
    var showsVisual = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if showsVisual {
                SocialResultVisual(result: result, compact: compact)
                    .accessibilityHidden(true)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.trickName)
                        .font(.system(size: compact ? 20 : 25, weight: .black, design: .rounded))
                        .tracking(-0.7)
                    Text(result.contextLabel)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(KamikazeTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let score = result.score {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(score)")
                            .font(.system(size: compact ? 29 : 38, weight: .black, design: .rounded))
                            .foregroundStyle(SocialVisuals.resultAccent(for: result))
                        Text("SCORE")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.muted)
                    }
                }
            }

            HStack(spacing: 14) {
                if let fit = result.fit {
                    SocialMetricValue(value: "\(fit)", label: "FIT")
                }
                SocialMetricValue(value: "\(result.durationMilliseconds) MS", label: "MOTION")
                if let landed = result.landed {
                    SocialMetricValue(
                        value: landed ? "LANDED" : "REVIEW",
                        label: "OUTCOME",
                        tint: landed ? KamikazeTheme.volt : KamikazeTheme.hazard
                    )
                }
                Spacer(minLength: 0)
                if attachments.contains(where: { $0.kind == .replayVideo }) {
                    SocialPill(title: "REPLAY", systemImage: "play.rectangle", tint: KamikazeTheme.ion)
                }
                if attachments.contains(where: { $0.kind == .sensorEvidence }) {
                    SocialPill(title: "EVIDENCE", systemImage: "waveform.path.ecg", tint: KamikazeTheme.hazard)
                }
            }
        }
        .padding(compact ? 14 : 18)
        .background(
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .fill(reduceTransparency ? KamikazeTheme.pitch.opacity(0.94) : .white.opacity(0.035))
        )
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 20 : 24, style: .continuous)
                .stroke(.white.opacity(reduceTransparency ? 0.18 : 0.09), lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(resultAccessibilityLabel)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: result.id)
    }

    private var resultAccessibilityLabel: String {
        var values = [result.trickName]
        if let score = result.score { values.append("score \(score)") }
        if let fit = result.fit { values.append("fit \(fit)") }
        values.append("motion \(result.durationMilliseconds) milliseconds")
        if let landed = result.landed { values.append(landed ? "landed" : "needs review") }
        return values.joined(separator: ", ")
    }
}

private struct SocialResultVisual: View {
    let result: SocialResultSnapshot
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let accent = SocialVisuals.resultAccent(for: result)
            let width = min(proxy.size.width * (compact ? 0.34 : 0.30), compact ? 106 : 132)
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.24), KamikazeTheme.pitch.opacity(0.82)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 19 + CGFloat(index) * 7, style: .continuous)
                        .stroke(accent.opacity(0.12 - Double(index) * 0.025), lineWidth: 1)
                        .rotationEffect(.degrees(Double(index - 1) * (reduceMotion ? 0 : 4)))
                        .scaleEffect(1 + CGFloat(index) * 0.075)
                }
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.75))
                    .overlay {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(accent)
                                .frame(width: 7, height: 7)
                            Text("K")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(KamikazeTheme.frost)
                        }
                    }
                    .frame(width: width, height: width * 1.64)
                    .rotationEffect(.degrees(reduceMotion ? 0 : -7))
                    .shadow(color: accent.opacity(0.24), radius: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: compact ? 112 : 164)
        .clipped()
    }
}

private struct SocialMetricValue: View {
    let value: String
    let label: String
    var tint: Color = KamikazeTheme.frost

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
        }
    }
}

// MARK: - Feed card and lightweight engagement

struct SocialPostCard: View {
    let post: SocialPost
    let viewerID: String
    let isReplayActive: Bool
    let onVisibilityChanged: (Bool) -> Void
    let onOpenProfile: () -> Void
    let onReaction: (SocialReaction?) -> Void
    let onComment: () -> Void
    let onUnpublish: () -> Void
    let onDelete: () -> Void
    let onModerate: () -> Void

    var body: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button(action: onOpenProfile) {
                        HStack(spacing: 10) {
                            SocialAvatarView(user: post.author, size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(post.author.displayName)
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                Text("@\(post.author.handle)  ·  \(relativeDate(post.publishedAt))")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this rider's profile")
                    Spacer()
                    SocialPill(
                        title: post.audience.title,
                        systemImage: post.audience.iconName,
                        tint: audienceTint
                    )
                    menu
                }

                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(KamikazeTheme.frost)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isReplayActive {
                    SocialFeedReplayView(post: post, isActive: true)
                }

                PublishedResultCardView(
                    result: post.result,
                    compact: true,
                    attachments: post.attachments,
                    showsVisual: !isReplayActive
                )

                SocialReactionBar(
                    counts: post.counts,
                    viewerReaction: post.viewerReaction,
                    onReaction: onReaction,
                    onComment: onComment
                )

                if !post.commentPreview.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(post.commentPreview) { comment in
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text(comment.author.handle)
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.muted)
                                Text(comment.body)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(KamikazeTheme.frost.opacity(0.86))
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if post.counts.comments > post.commentPreview.count {
                            Button("VIEW ALL \(post.counts.comments) COMMENTS", action: onComment)
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundStyle(KamikazeTheme.ion)
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .onScrollVisibilityChange(threshold: 0.62) { visible in
            onVisibilityChanged(visible)
        }
    }

    private var audienceTint: Color {
        switch post.audience {
        case .private: KamikazeTheme.muted
        case .friends: KamikazeTheme.ion
        case .public: KamikazeTheme.volt
        }
    }

    @ViewBuilder
    private var menu: some View {
        Menu {
            if post.author.id == viewerID {
                Button("Unpublish", systemImage: "eye.slash", action: onUnpublish)
                Button("Delete post", systemImage: "trash", role: .destructive, action: onDelete)
            } else {
                Button("Report post", systemImage: "flag", action: onModerate)
                Button("Report or block…", systemImage: "person.crop.circle.badge.xmark", action: onModerate)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(KamikazeTheme.muted)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(post.author.id == viewerID ? "Manage your post" : "More actions for this post")
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

struct SocialReactionBar: View {
    let counts: SocialEngagementCounts
    let viewerReaction: SocialReaction?
    let onReaction: (SocialReaction?) -> Void
    let onComment: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(SocialReaction.allCases) { reaction in
                Button {
                    onReaction(viewerReaction == reaction ? nil : reaction)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: reaction.iconName)
                        Text("\(counts.count(for: reaction))")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(viewerReaction == reaction ? KamikazeTheme.volt : KamikazeTheme.muted)
                    .frame(minWidth: 52, minHeight: 38)
                    .background(
                        (viewerReaction == reaction ? KamikazeTheme.volt : .white).opacity(0.07),
                        in: Capsule(style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(reaction.title) reaction")
                .accessibilityValue("\(counts.count(for: reaction))")
            }
            Button(action: onComment) {
                Label("\(counts.comments)", systemImage: "bubble.left")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.muted)
                    .frame(minWidth: 58, minHeight: 38)
                    .background(.white.opacity(0.07), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")
            .accessibilityValue("\(counts.comments)")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint("These are acknowledgements only; they do not affect score or progression.")
    }
}

// MARK: - Moderation placeholder

struct SocialModerationSheet: View {
    let post: SocialPost
    let onSubmit: (SocialModerationRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showBlockConfirmation = false
    @State private var reason = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ExperienceFieldBackground(ambient: KamikazeTheme.hazard)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            SocialAvatarView(user: post.author, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("KEEP THE FIELD USEFUL")
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(KamikazeTheme.hazard)
                                Text("Report or block @\(post.author.handle)")
                                    .font(.system(size: 21, weight: .black, design: .rounded))
                            }
                        }

                        Text("This is a local prototype placeholder. A future moderation service can attach the report to the post and author without changing this surface.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(KamikazeTheme.muted)

                        GlassSurface(role: .contentPanel, cornerRadius: 22) {
                            VStack(alignment: .leading, spacing: 12) {
                                SocialSectionLabel(title: "OPTIONAL NOTE", detail: "Only send what helps")
                                TextField("What should we know?", text: $reason, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .lineLimit(3...6)
                                    .padding(12)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .padding(16)
                        }

                        Button {
                            submit(.reportPost)
                        } label: {
                            Label("REPORT THIS POST", systemImage: "flag")
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .adaptiveGlassButton(tint: KamikazeTheme.hazard)

                        Button {
                            showBlockConfirmation = true
                        } label: {
                            Label("BLOCK @\(post.author.handle)", systemImage: "person.crop.circle.badge.xmark")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .adaptiveGlassButton(tint: KamikazeTheme.muted)
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                "Block @\(post.author.handle)?",
                isPresented: $showBlockConfirmation,
                titleVisibility: .visible
            ) {
                Button("Block profile", role: .destructive) { submit(.blockAuthor) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Their posts will disappear from this local feed. You can undo this once a real moderation backend is connected.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit(_ action: SocialModerationAction) {
        onSubmit(SocialModerationRequest(
            action: action,
            postID: post.id,
            authorID: post.author.id,
            reason: reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : reason
        ))
        dismiss()
    }
}

struct SocialCommentsSheet: View {
    let post: SocialPost
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ExperienceFieldBackground(ambient: KamikazeTheme.ion)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        PublishedResultCardView(result: post.result, compact: true, attachments: post.attachments)
                        if post.commentPreview.isEmpty {
                            ContentUnavailableView(
                                "No comments yet",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("Add a useful note about the throw.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            ForEach(post.commentPreview) { comment in
                                GlassSurface(role: .contentPanel, cornerRadius: 18) {
                                    HStack(alignment: .top, spacing: 10) {
                                        SocialAvatarView(user: comment.author, size: 32)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("@\(comment.author.handle)")
                                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                                .foregroundStyle(KamikazeTheme.muted)
                                            Text(comment.body)
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                        }
                                    }
                                    .padding(13)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    TextField("Add a comment", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .lineLimit(1...3)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    Button("Send") {
                        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !body.isEmpty else { return }
                        onSubmit(body)
                        draft = ""
                    }
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .frame(minWidth: 64, minHeight: 44)
                    .adaptiveGlassButton(tint: KamikazeTheme.ion)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(.black.opacity(0.45))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
