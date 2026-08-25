import Foundation

// MARK: - Audience and feed vocabulary

/// Visibility is an explicit part of a post. It is intentionally not inferred
/// from whether a replay or sensor payload is attached.
nonisolated enum SocialAudience: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case `private`
    case friends
    case `public`

    var id: String { rawValue }

    var title: String {
        switch self {
        case .private: "PRIVATE"
        case .friends: "FRIENDS"
        case .public: "PUBLIC"
        }
    }

    var detail: String {
        switch self {
        case .private: "Only you can see this result."
        case .friends: "People you follow and friends can see it."
        case .public: "Anyone with a Kamikaze profile can see it."
        }
    }

    var iconName: String {
        switch self {
        case .private: "lock.fill"
        case .friends: "person.2.fill"
        case .public: "globe"
        }
    }

    var accessibilityLabel: String {
        "\(title.capitalized). \(detail)"
    }
}

nonisolated enum SocialFeedScope: String, CaseIterable, Equatable, Sendable, Identifiable {
    case following
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .following: "FOLLOWING"
        case .discover: "DISCOVER"
        }
    }

    var subtitle: String {
        switch self {
        case .following: "Your circle, in motion."
        case .discover: "Public throws from the wider field."
        }
    }
}

nonisolated enum SocialPostState: String, Codable, Equatable, Sendable {
    case draft
    case published
    /// Kept for decoding prototype data. New unpublish operations return a
    /// post to `draft`, where it can be edited and published again.
    case unpublished
    case deleted
}

/// The social object is broader than a single detected attempt. Starting with
/// this vocabulary lets the same safe publishing boundary grow into lines and
/// community-authored trick proposals without treating either as raw media.
nonisolated enum SocialContentKind: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case run
    case line
    case trickProposal

    var id: String { rawValue }
}

/// Reactions are lightweight acknowledgements, not a score or ranking system.
/// The UI never turns them into streaks, rewards or popularity pressure.
nonisolated enum SocialReaction: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case respect
    case inspired
    case support

    var id: String { rawValue }

    var title: String {
        switch self {
        case .respect: "Respect"
        case .inspired: "Inspired"
        case .support: "Support"
        }
    }

    var iconName: String {
        switch self {
        case .respect: "hand.thumbsup"
        case .inspired: "sparkles"
        case .support: "heart"
        }
    }
}

nonisolated enum SocialAttachmentKind: String, Codable, Equatable, Sendable {
    case replayVideo
    case sensorEvidence
}

nonisolated enum SocialModerationAction: String, Codable, Equatable, Sendable {
    case reportPost
    case blockAuthor
}

// MARK: - Value contracts

nonisolated struct SocialUser: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let handle: String
    let displayName: String
    let initials: String
    /// Stable seed for a local avatar treatment. Persist a semantic seed, not
    /// a SwiftUI Color, so a future backend can render it consistently.
    let avatarSeed: Int
    var isFollowedByViewer: Bool

    init(
        id: String,
        handle: String,
        displayName: String,
        initials: String? = nil,
        avatarSeed: Int = 0,
        isFollowedByViewer: Bool = false
    ) {
        self.id = id
        self.handle = handle
        self.displayName = displayName
        self.initials = initials ?? SocialUser.makeInitials(from: displayName)
        self.avatarSeed = avatarSeed
        self.isFollowedByViewer = isFollowedByViewer
    }

    private static func makeInitials(from name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "-" })
        let letters = parts.prefix(2).compactMap { $0.first }
        let result = String(letters).uppercased()
        return result.isEmpty ? "K" : result
    }
}

/// A display-safe projection of a completed Result. It deliberately contains
/// no raw sensor samples or local file URLs; those are separate upload choices
/// in `SocialShareDraft`.
nonisolated struct SocialResultSnapshot: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let trickName: String
    let contextLabel: String
    let score: Int?
    let fit: Int?
    let durationMilliseconds: Int
    let landed: Bool?
    let capturedAt: Date
    /// Opaque local reference for a future upload worker or replay renderer.
    /// This is not a URL and is never sent by the mock repository.
    let replayReference: String?

    init(
        id: String,
        trickName: String,
        contextLabel: String = "NATIVE RESULT",
        score: Int? = nil,
        fit: Int? = nil,
        durationMilliseconds: Int = 0,
        landed: Bool? = nil,
        capturedAt: Date = .now,
        replayReference: String? = nil
    ) {
        self.id = id
        self.trickName = trickName
        self.contextLabel = contextLabel
        self.score = score.map { min(100, max(0, $0)) }
        self.fit = fit.map { min(100, max(0, $0)) }
        self.durationMilliseconds = max(0, durationMilliseconds)
        self.landed = landed
        self.capturedAt = capturedAt
        self.replayReference = replayReference
    }

    static let demo = SocialResultSnapshot(
        id: "attempt-demo-001",
        trickName: "PHONE FLIP",
        contextLabel: "RESULT  /  MOTION TAPE",
        score: 86,
        fit: 92,
        durationMilliseconds: 338,
        landed: true,
        capturedAt: Date(timeIntervalSince1970: 1_755_000_000),
        replayReference: "attempt-demo-001/replay"
    )
}

nonisolated struct SocialAttachment: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: SocialAttachmentKind
    /// Future Convex storage key. A local path must never be used as a public
    /// identifier; the mock uses this only as a placeholder.
    let localResourceID: String?
    let contentType: String
    let byteCount: Int?
    let sha256: String?

    init(
        id: String,
        kind: SocialAttachmentKind,
        localResourceID: String? = nil,
        contentType: String,
        byteCount: Int? = nil,
        sha256: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.localResourceID = localResourceID
        self.contentType = contentType
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

/// Consent is recorded with the exact upload classes selected by the player.
/// Selecting an audience alone never grants permission to upload evidence.
nonisolated struct SocialUploadConsent: Codable, Equatable, Hashable, Sendable {
    static let currentVersion = "social-upload-consent-v1"

    let version: String
    let accepted: Bool
    let acceptedAt: Date?

    init(
        version: String = Self.currentVersion,
        accepted: Bool = false,
        acceptedAt: Date? = nil
    ) {
        self.version = version
        self.accepted = accepted
        self.acceptedAt = acceptedAt
    }

    func isValid(forReplayVideo: Bool, sensorEvidence: Bool) -> Bool {
        guard forReplayVideo || sensorEvidence else { return true }
        return accepted && acceptedAt != nil && version == Self.currentVersion
    }
}

nonisolated struct SocialShareDraft: Codable, Equatable, Sendable {
    /// Stable client identity makes offline saves and Convex retries
    /// idempotent. It is never derived from a local filesystem path.
    let id: String
    var contentKind: SocialContentKind
    let result: SocialResultSnapshot
    var caption: String
    var audience: SocialAudience
    var includeReplayVideo: Bool
    var includeSensorEvidence: Bool
    var uploadConsent: SocialUploadConsent

    init(
        id: String = UUID().uuidString,
        contentKind: SocialContentKind = .run,
        result: SocialResultSnapshot,
        caption: String = "",
        audience: SocialAudience = .private,
        includeReplayVideo: Bool = false,
        includeSensorEvidence: Bool = false,
        uploadConsent: SocialUploadConsent = SocialUploadConsent()
    ) {
        self.id = id
        self.contentKind = contentKind
        self.result = result
        self.caption = caption
        self.audience = audience
        self.includeReplayVideo = includeReplayVideo
        self.includeSensorEvidence = includeSensorEvidence
        self.uploadConsent = uploadConsent
    }

    var trimmedCaption: String { caption.trimmingCharacters(in: .whitespacesAndNewlines) }

    var requiresExplicitConsent: Bool { includeReplayVideo || includeSensorEvidence }

    var canPublish: Bool {
        trimmedCaption.count <= 280 && uploadConsent.isValid(
            forReplayVideo: includeReplayVideo,
            sensorEvidence: includeSensorEvidence
        )
    }

    var validationMessage: String? {
        guard trimmedCaption.count <= 280 else { return "Keep the caption under 280 characters." }
        guard uploadConsent.isValid(
            forReplayVideo: includeReplayVideo,
            sensorEvidence: includeSensorEvidence
        ) else {
            return "Confirm the upload choices before publishing."
        }
        return nil
    }
}

nonisolated struct SocialEngagementCounts: Codable, Equatable, Hashable, Sendable {
    var reactions: Int
    var comments: Int
    var reactionBreakdown: [String: Int]

    init(
        reactions: Int = 0,
        comments: Int = 0,
        reactionBreakdown: [String: Int] = [:]
    ) {
        self.reactions = max(0, reactions)
        self.comments = max(0, comments)
        self.reactionBreakdown = reactionBreakdown
    }

    func count(for reaction: SocialReaction) -> Int {
        max(0, reactionBreakdown[reaction.rawValue] ?? 0)
    }
}

nonisolated struct SocialComment: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let postID: String
    let author: SocialUser
    let body: String
    let createdAt: Date
}

nonisolated struct SocialPost: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let contentKind: SocialContentKind
    /// Stable local attempt reference. It is separate from the post ID so a
    /// player can unpublish/delete a social record without deleting evidence.
    let attemptID: String
    let author: SocialUser
    let result: SocialResultSnapshot
    let caption: String
    let audience: SocialAudience
    let attachments: [SocialAttachment]
    let publishedAt: Date
    let state: SocialPostState
    let counts: SocialEngagementCounts
    let viewerReaction: SocialReaction?
    let commentPreview: [SocialComment]

    var isVisible: Bool { state == .published }
    var hasReplayVideo: Bool { attachments.contains { $0.kind == .replayVideo } }
    var hasSensorEvidence: Bool { attachments.contains { $0.kind == .sensorEvidence } }

    init(
        id: String,
        contentKind: SocialContentKind = .run,
        attemptID: String,
        author: SocialUser,
        result: SocialResultSnapshot,
        caption: String,
        audience: SocialAudience,
        attachments: [SocialAttachment],
        publishedAt: Date,
        state: SocialPostState,
        counts: SocialEngagementCounts,
        viewerReaction: SocialReaction?,
        commentPreview: [SocialComment]
    ) {
        self.id = id
        self.contentKind = contentKind
        self.attemptID = attemptID
        self.author = author
        self.result = result
        self.caption = caption
        self.audience = audience
        self.attachments = attachments
        self.publishedAt = publishedAt
        self.state = state
        self.counts = counts
        self.viewerReaction = viewerReaction
        self.commentPreview = commentPreview
    }
}

nonisolated struct SocialProfileSummary: Codable, Equatable, Sendable {
    let profile: SocialUser
    let followingCount: Int
    let followerCount: Int
    let publishedCount: Int
    let friendsCount: Int
    let defaultAudience: SocialAudience

    var totalConnections: Int { followingCount + followerCount }
}

nonisolated struct SocialModerationRequest: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let action: SocialModerationAction
    let postID: String?
    let authorID: String
    let reason: String?
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        action: SocialModerationAction,
        postID: String? = nil,
        authorID: String,
        reason: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.action = action
        self.postID = postID
        self.authorID = authorID
        self.reason = reason
        self.createdAt = createdAt
    }
}

nonisolated enum SocialRepositoryError: Error, Equatable, Sendable {
    case validation(String)
    case notFound
    case unauthorized
    case blocked
    case unavailable

    var message: String {
        switch self {
        case let .validation(message): message
        case .notFound: "That result is no longer available."
        case .unauthorized: "This action is only available to the post owner."
        case .blocked: "This profile is blocked."
        case .unavailable: "Social preview data is unavailable right now."
        }
    }
}

// MARK: - Repository contract

/// Async value-based boundary for a future Convex implementation. The local
/// actor below is deliberately the only implementation shipped in this
/// prototype; no request, auth, or network code belongs in Social views.
protocol SocialRepository: Sendable {
    func fetchFeed(scope: SocialFeedScope) async throws -> [SocialPost]
    func fetchMyDrafts() async throws -> [SocialPost]
    func fetchProfileSummary() async throws -> SocialProfileSummary
    func saveDraft(_ draft: SocialShareDraft) async throws -> SocialPost
    func publish(_ draft: SocialShareDraft) async throws -> SocialPost
    func unpublish(postID: String) async throws
    func deletePost(postID: String) async throws
    func setReaction(_ reaction: SocialReaction?, on postID: String) async throws -> SocialPost
    func addComment(_ body: String, to postID: String) async throws -> SocialComment
    func submitModeration(_ request: SocialModerationRequest) async throws
}
