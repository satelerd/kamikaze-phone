import Foundation

/// Deterministic seed data for previews, simulator walkthroughs and unit
/// tests. The values look like a small living circle, but nothing here leaves
/// the device.
nonisolated struct SocialMockSeed: Sendable {
    let viewer: SocialUser
    let posts: [SocialPost]
    let followingCount: Int
    let followerCount: Int
    let friendsCount: Int
    let defaultAudience: SocialAudience

    static var standard: Self {
        let viewer = SocialUser(
            id: "user-sat",
            handle: "sat",
            displayName: "Daniel Sateler",
            initials: "DS",
            avatarSeed: 1
        )
        let mara = SocialUser(
            id: "user-mara",
            handle: "mara.moves",
            displayName: "Mara Rojas",
            initials: "MR",
            avatarSeed: 2,
            isFollowedByViewer: true
        )
        let tom = SocialUser(
            id: "user-tom",
            handle: "tom.loop",
            displayName: "Tomás Loop",
            initials: "TL",
            avatarSeed: 3,
            isFollowedByViewer: true
        )
        let jules = SocialUser(
            id: "user-jules",
            handle: "jules.axis",
            displayName: "Jules Axis",
            initials: "JA",
            avatarSeed: 4
        )
        let riley = SocialUser(
            id: "user-riley",
            handle: "riley.catch",
            displayName: "Riley Catch",
            initials: "RC",
            avatarSeed: 5
        )

        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let maraResult = SocialResultSnapshot(
            id: "attempt-mara-001",
            trickName: "REVERSE PHONE FLIP",
            contextLabel: "RESULT  /  FRIENDS",
            score: 78,
            fit: 88,
            durationMilliseconds: 372,
            landed: true,
            capturedAt: now.addingTimeInterval(-2_400),
            replayReference: "attempt-mara-001/replay"
        )
        let tomResult = SocialResultSnapshot(
            id: "attempt-tom-001",
            trickName: "FRONTSIDE SHUVIT",
            contextLabel: "RESULT  /  FRIENDS",
            score: 71,
            fit: 80,
            durationMilliseconds: 426,
            landed: true,
            capturedAt: now.addingTimeInterval(-5_900),
            replayReference: "attempt-tom-001/replay"
        )
        let julesResult = SocialResultSnapshot(
            id: "attempt-jules-001",
            trickName: "PHONE FLIP",
            contextLabel: "RESULT  /  DISCOVER",
            score: 93,
            fit: 96,
            durationMilliseconds: 304,
            landed: true,
            capturedAt: now.addingTimeInterval(-28_800),
            replayReference: "attempt-jules-001/replay"
        )
        let rileyResult = SocialResultSnapshot(
            id: "attempt-riley-001",
            trickName: "STRAIGHT AIR",
            contextLabel: "RESULT  /  DISCOVER",
            score: nil,
            fit: nil,
            durationMilliseconds: 512,
            landed: nil,
            capturedAt: now.addingTimeInterval(-82_000),
            replayReference: "attempt-riley-001/replay"
        )

        let maraComment = SocialComment(
            id: "comment-mara-001",
            postID: "post-mara-001",
            author: tom,
            body: "The catch stayed quiet. Nice one.",
            createdAt: now.addingTimeInterval(-1_700)
        )
        let tomComment = SocialComment(
            id: "comment-tom-001",
            postID: "post-tom-001",
            author: mara,
            body: "That axis is getting clean.",
            createdAt: now.addingTimeInterval(-5_100)
        )

        let posts = [
            SocialPost(
                id: "post-mara-001",
                attemptID: maraResult.id,
                author: mara,
                result: maraResult,
                caption: "Low release, calm catch. Keeping the phone close.",
                audience: .friends,
                attachments: [SocialAttachment(
                    id: "attachment-mara-001",
                    kind: .replayVideo,
                    localResourceID: "attempt-mara-001/replay",
                    contentType: "video/mp4"
                )],
                publishedAt: now.addingTimeInterval(-2_400),
                state: .published,
                counts: SocialEngagementCounts(
                    reactions: 6,
                    comments: 1,
                    reactionBreakdown: [
                        SocialReaction.respect.rawValue: 4,
                        SocialReaction.inspired.rawValue: 2,
                    ]
                ),
                viewerReaction: .respect,
                commentPreview: [maraComment]
            ),
            SocialPost(
                id: "post-tom-001",
                attemptID: tomResult.id,
                author: tom,
                result: tomResult,
                caption: "A little slower than yesterday. More rotation, less panic.",
                audience: .friends,
                attachments: [],
                publishedAt: now.addingTimeInterval(-5_900),
                state: .published,
                counts: SocialEngagementCounts(
                    reactions: 3,
                    comments: 1,
                    reactionBreakdown: [SocialReaction.support.rawValue: 3]
                ),
                viewerReaction: nil,
                commentPreview: [tomComment]
            ),
            SocialPost(
                id: "post-jules-001",
                attemptID: julesResult.id,
                author: jules,
                result: julesResult,
                caption: "Three clean reads from the same setup. Sharing the result, not a leaderboard.",
                audience: .public,
                attachments: [SocialAttachment(
                    id: "attachment-jules-001",
                    kind: .replayVideo,
                    localResourceID: "attempt-jules-001/replay",
                    contentType: "video/mp4"
                )],
                publishedAt: now.addingTimeInterval(-28_800),
                state: .published,
                counts: SocialEngagementCounts(
                    reactions: 19,
                    comments: 4,
                    reactionBreakdown: [
                        SocialReaction.respect.rawValue: 11,
                        SocialReaction.inspired.rawValue: 8,
                    ]
                ),
                viewerReaction: nil,
                commentPreview: []
            ),
            SocialPost(
                id: "post-riley-001",
                attemptID: rileyResult.id,
                author: riley,
                result: rileyResult,
                caption: "Trying to understand the air window before naming the trick.",
                audience: .public,
                attachments: [],
                publishedAt: now.addingTimeInterval(-82_000),
                state: .published,
                counts: SocialEngagementCounts(
                    reactions: 2,
                    comments: 0,
                    reactionBreakdown: [SocialReaction.support.rawValue: 2]
                ),
                viewerReaction: nil,
                commentPreview: []
            ),
        ]

        return SocialMockSeed(
            viewer: viewer,
            posts: posts,
            followingCount: 8,
            followerCount: 14,
            friendsCount: 5,
            defaultAudience: .friends
        )
    }
}

/// Local-only repository. Its API is deliberately async so a later Convex
/// adapter can replace it without changing view code or the data contract.
actor MockSocialRepository: SocialRepository {
    let viewer: SocialUser

    private var postsByID: [String: SocialPost]
    private var postOrder: [String]
    private var followingCount: Int
    private var followerCount: Int
    private var friendsCount: Int
    private var defaultAudience: SocialAudience
    private var blockedAuthorIDs: Set<String> = []
    private var moderationRequests: [SocialModerationRequest] = []
    private var nextPostNumber = 100
    private var nextCommentNumber = 100

    init(seed: SocialMockSeed = .standard) {
        viewer = seed.viewer
        postsByID = Dictionary(uniqueKeysWithValues: seed.posts.map { ($0.id, $0) })
        postOrder = seed.posts.map(\.id)
        followingCount = seed.followingCount
        followerCount = seed.followerCount
        friendsCount = seed.friendsCount
        defaultAudience = seed.defaultAudience
    }

    func fetchFeed(scope: SocialFeedScope) async throws -> [SocialPost] {
        postsByID.values
            .filter { post in
                guard post.isVisible, !blockedAuthorIDs.contains(post.author.id) else { return false }
                switch scope {
                case .following:
                    return post.author.id == viewer.id
                        || post.author.isFollowedByViewer
                        || post.audience == .friends && post.author.id == viewer.id
                case .discover:
                    return post.audience == .public && post.author.id != viewer.id
                }
            }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    func fetchProfileSummary() async throws -> SocialProfileSummary {
        let publishedCount = postsByID.values.count {
            $0.author.id == viewer.id && $0.state == .published
        }
        return SocialProfileSummary(
            profile: viewer,
            followingCount: followingCount,
            followerCount: followerCount,
            publishedCount: publishedCount,
            friendsCount: friendsCount,
            defaultAudience: defaultAudience
        )
    }

    func publish(_ draft: SocialShareDraft) async throws -> SocialPost {
        guard draft.canPublish else {
            throw SocialRepositoryError.validation(
                draft.validationMessage ?? "This result is not ready to publish."
            )
        }

        let postID = "post-local-\(nextPostNumber)"
        nextPostNumber += 1
        var attachments: [SocialAttachment] = []
        if draft.includeReplayVideo {
            attachments.append(SocialAttachment(
                id: "attachment-\(postID)-replay",
                kind: .replayVideo,
                localResourceID: draft.result.replayReference,
                contentType: "video/mp4"
            ))
        }
        if draft.includeSensorEvidence {
            attachments.append(SocialAttachment(
                id: "attachment-\(postID)-evidence",
                kind: .sensorEvidence,
                localResourceID: "attempt/\(draft.result.id)/sensor-evidence",
                contentType: "application/json"
            ))
        }

        let post = SocialPost(
            id: postID,
            attemptID: draft.result.id,
            author: viewer,
            result: draft.result,
            caption: draft.trimmedCaption,
            audience: draft.audience,
            attachments: attachments,
            publishedAt: .now,
            state: .published,
            counts: SocialEngagementCounts(),
            viewerReaction: nil,
            commentPreview: []
        )
        postsByID[post.id] = post
        postOrder.insert(post.id, at: 0)
        return post
    }

    func unpublish(postID: String) async throws {
        guard let post = postsByID[postID] else { throw SocialRepositoryError.notFound }
        guard post.author.id == viewer.id else { throw SocialRepositoryError.unauthorized }
        postsByID[postID] = replacing(post, state: .unpublished)
    }

    func deletePost(postID: String) async throws {
        guard let post = postsByID[postID] else { throw SocialRepositoryError.notFound }
        guard post.author.id == viewer.id else { throw SocialRepositoryError.unauthorized }
        postsByID.removeValue(forKey: postID)
        postOrder.removeAll { $0 == postID }
    }

    func setReaction(_ reaction: SocialReaction?, on postID: String) async throws -> SocialPost {
        guard let post = postsByID[postID], post.isVisible else { throw SocialRepositoryError.notFound }
        guard !blockedAuthorIDs.contains(post.author.id) else { throw SocialRepositoryError.blocked }
        guard post.viewerReaction != reaction else { return post }

        var breakdown = post.counts.reactionBreakdown
        var total = post.counts.reactions
        if let previous = post.viewerReaction {
            let nextCount = max(0, (breakdown[previous.rawValue] ?? 0) - 1)
            breakdown[previous.rawValue] = nextCount == 0 ? nil : nextCount
            total = max(0, total - 1)
        }
        if let reaction {
            breakdown[reaction.rawValue] = (breakdown[reaction.rawValue] ?? 0) + 1
            total += 1
        }

        let updated = replacing(
            post,
            counts: SocialEngagementCounts(
                reactions: total,
                comments: post.counts.comments,
                reactionBreakdown: breakdown
            ),
            viewerReaction: reaction
        )
        postsByID[postID] = updated
        return updated
    }

    func addComment(_ body: String, to postID: String) async throws -> SocialComment {
        guard let post = postsByID[postID], post.isVisible else { throw SocialRepositoryError.notFound }
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBody.isEmpty, cleanBody.count <= 280 else {
            throw SocialRepositoryError.validation("Comments are 1–280 characters.")
        }
        let comment = SocialComment(
            id: "comment-local-(nextCommentNumber)",
            postID: postID,
            author: viewer,
            body: cleanBody,
            createdAt: .now
        )
        nextCommentNumber += 1
        var comments = post.commentPreview
        comments.append(comment)
        comments = Array(comments.suffix(2))
        let updated = replacing(
            post,
            counts: SocialEngagementCounts(
                reactions: post.counts.reactions,
                comments: post.counts.comments + 1,
                reactionBreakdown: post.counts.reactionBreakdown
            ),
            commentPreview: comments
        )
        postsByID[postID] = updated
        return comment
    }

    func submitModeration(_ request: SocialModerationRequest) async throws {
        guard !request.authorID.isEmpty else {
            throw SocialRepositoryError.validation("A moderation target is required.")
        }
        if let postID = request.postID, postsByID[postID] == nil {
            throw SocialRepositoryError.notFound
        }
        moderationRequests.append(request)
        if request.action == .blockAuthor {
            blockedAuthorIDs.insert(request.authorID)
        }
    }

    private func replacing(
        _ post: SocialPost,
        state: SocialPostState? = nil,
        counts: SocialEngagementCounts? = nil,
        viewerReaction: SocialReaction?? = nil,
        commentPreview: [SocialComment]? = nil
    ) -> SocialPost {
        SocialPost(
            id: post.id,
            attemptID: post.attemptID,
            author: post.author,
            result: post.result,
            caption: post.caption,
            audience: post.audience,
            attachments: post.attachments,
            publishedAt: post.publishedAt,
            state: state ?? post.state,
            counts: counts ?? post.counts,
            viewerReaction: viewerReaction ?? post.viewerReaction,
            commentPreview: commentPreview ?? post.commentPreview
        )
    }
}
