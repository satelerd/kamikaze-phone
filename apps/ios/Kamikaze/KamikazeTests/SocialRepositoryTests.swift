import XCTest
@testable import Kamikaze

@MainActor
final class SocialRepositoryTests: XCTestCase {
    func testFeedsSeparateFollowingAndPublicDiscover() async throws {
        let repository = MockSocialRepository()

        let following = try await repository.fetchFeed(scope: .following)
        let discover = try await repository.fetchFeed(scope: .discover)

        XCTAssertFalse(following.isEmpty)
        XCTAssertFalse(discover.isEmpty)
        XCTAssertTrue(following.allSatisfy { $0.audience != .public || $0.author.isFollowedByViewer || $0.author.id == "user-sat" })
        XCTAssertTrue(discover.allSatisfy { $0.audience == .public })
        XCTAssertTrue(discover.allSatisfy { $0.author.id != "user-sat" })
    }

    func testPublishResultCardWithoutAttachmentsNeedsNoConsent() async throws {
        let repository = MockSocialRepository()
        let draft = SocialShareDraft(result: .demo, caption: "Card only", audience: .friends)

        let post = try await repository.publish(draft)

        XCTAssertEqual(post.author.id, "user-sat")
        XCTAssertEqual(post.audience, .friends)
        XCTAssertTrue(post.attachments.isEmpty)
        XCTAssertEqual(post.caption, "Card only")
    }

    func testDraftKeepsStableIdentityUntilPublished() async throws {
        let repository = MockSocialRepository()
        let draft = SocialShareDraft(
            id: "draft-line-1",
            contentKind: .line,
            result: .demo,
            caption: "Working title",
            audience: .private
        )

        let saved = try await repository.saveDraft(draft)
        XCTAssertEqual(saved.id, draft.id)
        XCTAssertEqual(saved.state, .draft)
        XCTAssertEqual(saved.contentKind, .line)
        let feedBeforePublish = try await repository.fetchFeed(scope: .following)
        let draftsBeforePublish = try await repository.fetchMyDrafts()
        XCTAssertTrue(feedBeforePublish.allSatisfy { $0.id != draft.id })
        XCTAssertEqual(draftsBeforePublish.map(\.id), [draft.id])

        let published = try await repository.publish(draft)
        XCTAssertEqual(published.id, draft.id)
        XCTAssertEqual(published.state, .published)
        let draftsAfterPublish = try await repository.fetchMyDrafts()
        let feedAfterPublish = try await repository.fetchFeed(scope: .following)
        XCTAssertTrue(draftsAfterPublish.isEmpty)
        XCTAssertEqual(feedAfterPublish.filter { $0.id == draft.id }.count, 1)
    }

    func testPublishWithSensorEvidenceRequiresExplicitConsent() async throws {
        let repository = MockSocialRepository()
        var draft = SocialShareDraft(
            result: .demo,
            audience: .public,
            includeSensorEvidence: true
        )

        do {
            _ = try await repository.publish(draft)
            XCTFail("Sensor evidence should require consent")
        } catch let error as SocialRepositoryError {
            guard case .validation = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        draft.uploadConsent = SocialUploadConsent(
            accepted: true,
            acceptedAt: Date(timeIntervalSince1970: 1_755_000_000)
        )
        let post = try await repository.publish(draft)
        XCTAssertTrue(post.hasSensorEvidence)
        XCTAssertEqual(post.audience, .public)
    }

    func testReactionReplacesAndRemovesViewerReaction() async throws {
        let repository = MockSocialRepository()
        let following = try await repository.fetchFeed(scope: .following)
        let post = try XCTUnwrap(following.first)
        let initialTotal = post.counts.reactions

        let respected = try await repository.setReaction(.respect, on: post.id)
        XCTAssertEqual(respected.viewerReaction, .respect)
        XCTAssertEqual(respected.counts.reactions, initialTotal + (post.viewerReaction == nil ? 1 : 0))

        let removed = try await repository.setReaction(nil, on: post.id)
        XCTAssertNil(removed.viewerReaction)
        XCTAssertEqual(removed.counts.reactions, initialTotal - (post.viewerReaction == nil ? 0 : 1))
    }

    func testUnpublishHidesPostButDeleteRemovesIt() async throws {
        let repository = MockSocialRepository()
        let post = try await repository.publish(SocialShareDraft(result: .demo))

        try await repository.unpublish(postID: post.id)
        let afterUnpublish = try await repository.fetchFeed(scope: .following)
        let draftsAfterUnpublish = try await repository.fetchMyDrafts()
        XCTAssertFalse(afterUnpublish.contains { $0.id == post.id })
        XCTAssertEqual(draftsAfterUnpublish.map(\.id), [post.id])

        try await repository.deletePost(postID: post.id)
        do {
            try await repository.deletePost(postID: post.id)
            XCTFail("Deleted post should not be available")
        } catch let error as SocialRepositoryError {
            XCTAssertEqual(error, .notFound)
        }
    }

    func testBlockRemovesAuthorFromFutureFeeds() async throws {
        let repository = MockSocialRepository()
        let discoverBefore = try await repository.fetchFeed(scope: .discover)
        let post = try XCTUnwrap(discoverBefore.first)
        let request = SocialModerationRequest(
            action: .blockAuthor,
            postID: post.id,
            authorID: post.author.id
        )

        try await repository.submitModeration(request)
        let discover = try await repository.fetchFeed(scope: .discover)
        XCTAssertFalse(discover.contains { $0.author.id == post.author.id })
    }

    func testCommentsReceiveDistinctStableIDs() async throws {
        let repository = MockSocialRepository()
        let post = try await repository.publish(SocialShareDraft(result: .demo))

        let first = try await repository.addComment("First", to: post.id)
        let second = try await repository.addComment("Second", to: post.id)

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(first.id.hasPrefix("comment-local-"))
        XCTAssertTrue(second.id.hasPrefix("comment-local-"))
    }
}
