import Observation
import SwiftUI

@MainActor
@Observable
final class SocialFeedModel {
    let repository: any SocialRepository

    var scope: SocialFeedScope = .following
    private(set) var posts: [SocialPost] = []
    private(set) var profileSummary: SocialProfileSummary?
    private(set) var isLoading = false
    private(set) var isMutating = false
    private(set) var errorMessage: String?

    init(repository: any SocialRepository) {
        self.repository = repository
    }

    var viewerID: String { profileSummary?.profile.id ?? "user-sat" }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let fetchedPosts = repository.fetchFeed(scope: scope)
            async let fetchedProfile = repository.fetchProfileSummary()
            posts = try await fetchedPosts
            profileSummary = try await fetchedProfile
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func changeScope(to newScope: SocialFeedScope) async {
        scope = newScope
        await reloadFeedOnly()
    }

    func react(_ reaction: SocialReaction?, on post: SocialPost) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            let updated = try await repository.setReaction(reaction, on: post.id)
            replace(updated)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func comment(_ body: String, on post: SocialPost) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            _ = try await repository.addComment(body, to: post.id)
            await reloadFeedOnly()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func unpublish(_ post: SocialPost) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await repository.unpublish(postID: post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func delete(_ post: SocialPost) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await repository.deletePost(postID: post.id)
            posts.removeAll { $0.id == post.id }
            if profileSummary != nil {
                profileSummary = try await repository.fetchProfileSummary()
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func moderate(_ request: SocialModerationRequest) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await repository.submitModeration(request)
            if request.action == .blockAuthor {
                posts.removeAll { $0.author.id == request.authorID }
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func reloadFeedOnly() async {
        do {
            posts = try await repository.fetchFeed(scope: scope)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func replace(_ post: SocialPost) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        posts[index] = post
    }

    private static func message(for error: Error) -> String {
        if let socialError = error as? SocialRepositoryError { return socialError.message }
        return error.localizedDescription
    }
}

/// Following and Discover share the player-facing Feed tab. The repository
/// boundary remains injectable while Convex publishing evolves; the view has
/// no manual refresh affordance because the production source is reactive.
struct SocialFeedView: View {
    @State private var model: SocialFeedModel
    @State private var commentsPost: SocialPost?
    @State private var moderationPost: SocialPost?
    @State private var pendingManagement: SocialPendingPostAction?
    @State private var selectedProfile: SocialUser?
    @State private var activePostID: String?
    @State private var showsTrickExchange = false

    init(repository: any SocialRepository = MockSocialRepository()) {
        _model = State(initialValue: SocialFeedModel(repository: repository))
    }

    var body: some View {
        @Bindable var model = model

        ZStack {
            ExperienceFieldBackground(ambient: KamikazeTheme.ion)
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    header
                    SocialFeedScopePicker(selection: $model.scope) { selected in
                        Task { await model.changeScope(to: selected) }
                    }

                    if model.isLoading && model.posts.isEmpty {
                        ProgressView()
                            .tint(KamikazeTheme.volt)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else if let errorMessage = model.errorMessage, model.posts.isEmpty {
                        SocialFeedEmptyState(
                            title: "FEED PAUSED",
                            detail: errorMessage,
                            actionTitle: "TRY AGAIN"
                        ) {
                            Task { await model.load() }
                        }
                    } else if model.posts.isEmpty {
                        SocialFeedEmptyState(
                            title: model.scope == .following ? "YOUR CIRCLE IS QUIET" : "NO PUBLIC THROWS YET",
                            detail: model.scope == .following
                                ? "Follow a rider or publish a result to start a calm, chronological feed."
                                : "Public results will appear here when riders choose to share them.",
                            actionTitle: "CREATE A TRICK"
                        ) {
                            showsTrickExchange = true
                        }
                    } else {
                        feedNote
                        ForEach(model.posts) { post in
                            SocialPostCard(
                                post: post,
                                viewerID: model.viewerID,
                                isReplayActive: activePostID == post.id,
                                onVisibilityChanged: { visible in
                                    if visible {
                                        activePostID = post.id
                                    } else if activePostID == post.id {
                                        activePostID = nil
                                    }
                                },
                                onOpenProfile: { selectedProfile = post.author },
                                onReaction: { reaction in
                                    Task { await model.react(reaction, on: post) }
                                },
                                onComment: {
                                    commentsPost = post
                                },
                                onUnpublish: {
                                    pendingManagement = SocialPendingPostAction(post: post, kind: .unpublish)
                                },
                                onDelete: {
                                    pendingManagement = SocialPendingPostAction(post: post, kind: .delete)
                                },
                                onModerate: {
                                    moderationPost = post
                                }
                            )
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 100)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await model.load()
        }
        .navigationDestination(item: $selectedProfile) { profile in
            SocialPublicProfileView(
                user: profile,
                posts: model.posts.filter { $0.author.id == profile.id }
            )
        }
        .navigationDestination(isPresented: $showsTrickExchange) {
            CommunityTrickExchangeView()
        }
        .sheet(item: $commentsPost) { post in
            SocialCommentsSheet(post: post) { body in
                Task { await model.comment(body, on: post) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $moderationPost) { post in
            SocialModerationSheet(post: post) { request in
                Task { await model.moderate(request) }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            managementTitle,
            isPresented: Binding(
                get: { pendingManagement != nil },
                set: { isPresented in
                    if !isPresented { pendingManagement = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            if pendingManagement?.kind == .unpublish {
                Button("Unpublish", role: .destructive) {
                    if let post = pendingManagement?.post {
                        Task { await model.unpublish(post) }
                    }
                    pendingManagement = nil
                }
            } else {
                Button("Delete permanently", role: .destructive) {
                    if let post = pendingManagement?.post {
                        Task { await model.delete(post) }
                    }
                    pendingManagement = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingManagement = nil }
        } message: {
            Text(managementMessage)
        }
        .alert("Social preview", isPresented: Binding(
            get: { model.errorMessage != nil && !model.posts.isEmpty },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("FOLLOW\nTHE THROW")
                    .font(.system(size: 37, weight: .black, design: .rounded))
                    .tracking(-1.5)
                Text("RESULTS FROM PEOPLE, WITHOUT THE NOISE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(KamikazeTheme.ion)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NavigationLink {
                CommunityTrickExchangeView()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 44, height: 44)
            }
            .adaptiveGlassButton(tint: KamikazeTheme.volt)
            .accessibilityLabel("Create or teach a community trick")
        }
    }

    private var feedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .foregroundStyle(KamikazeTheme.volt)
            Text("AUTOPLAY 3D  ·  CHRONOLOGICAL  ·  NO STREAK PRESSURE")
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(KamikazeTheme.muted)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var managementTitle: String {
        switch pendingManagement?.kind {
        case .unpublish: "Unpublish this result?"
        case .delete: "Delete this result?"
        case nil: "Manage result"
        }
    }

    private var managementMessage: String {
        switch pendingManagement?.kind {
        case .unpublish: "It will disappear from feeds but remain available locally for a future re-share."
        case .delete: "This removes the published social record. Your original local attempt stays untouched."
        case nil: ""
        }
    }
}

private struct SocialPendingPostAction {
    enum Kind {
        case unpublish
        case delete
    }

    let post: SocialPost
    let kind: Kind
}

struct SocialFeedScopePicker: View {
    @Binding var selection: SocialFeedScope
    let onSelect: (SocialFeedScope) -> Void

    var body: some View {
        GlassSurface(role: .instrumentHUD, cornerRadius: 18) {
            HStack(spacing: 4) {
                ForEach(SocialFeedScope.allCases) { scope in
                    Button {
                        selection = scope
                        onSelect(scope)
                    } label: {
                        VStack(spacing: 4) {
                            Text(scope.title)
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                            Text(scope.subtitle)
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(selection == scope ? KamikazeTheme.frost : KamikazeTheme.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            selection == scope ? KamikazeTheme.ion.opacity(0.17) : .clear,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == scope ? KamikazeTheme.ion : KamikazeTheme.muted)
                    .accessibilityLabel(scope.title.capitalized)
                    .accessibilityValue(selection == scope ? "Selected" : "Not selected")
                }
            }
            .padding(5)
        }
    }
}

struct SocialFeedEmptyState: View {
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        GlassSurface(role: .contentPanel, cornerRadius: 24) {
            VStack(spacing: 13) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 29, weight: .bold))
                    .foregroundStyle(KamikazeTheme.ion)
                Text(title)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                Text(detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(KamikazeTheme.muted)
                    .multilineTextAlignment(.center)
                Button(actionTitle, action: action)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .frame(minWidth: 130, minHeight: 44)
                    .adaptiveGlassButton(tint: KamikazeTheme.ion)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
    }
}
