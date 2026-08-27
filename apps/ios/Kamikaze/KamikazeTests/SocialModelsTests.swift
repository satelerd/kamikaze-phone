import XCTest
@testable import Kamikaze

final class SocialModelsTests: XCTestCase {
    func testAudienceCopyAndAccessibilityStayExplicit() {
        XCTAssertEqual(SocialAudience.private.title, "PRIVATE")
        XCTAssertTrue(SocialAudience.friends.accessibilityLabel.contains("Friends"))
        XCTAssertTrue(SocialAudience.public.detail.contains("Anyone"))
    }

    func testSnapshotClampsPresentationValuesWithoutTouchingIdentity() {
        let snapshot = SocialResultSnapshot(
            id: "attempt-1",
            trickName: "PHONE FLIP",
            score: 140,
            fit: -4,
            durationMilliseconds: -20
        )

        XCTAssertEqual(snapshot.id, "attempt-1")
        XCTAssertEqual(snapshot.score, 100)
        XCTAssertEqual(snapshot.fit, 0)
        XCTAssertEqual(snapshot.durationMilliseconds, 0)
    }

    func testConsentIsRequiredOnlyForSelectedUploads() {
        var draft = SocialShareDraft(result: .demo)
        XCTAssertTrue(draft.canPublish)

        draft.includeReplayVideo = true
        XCTAssertFalse(draft.canPublish)
        XCTAssertNotNil(draft.validationMessage)

        draft.uploadConsent = SocialUploadConsent(
            accepted: true,
            acceptedAt: Date(timeIntervalSince1970: 1_755_000_000)
        )
        XCTAssertTrue(draft.canPublish)

        draft.includeReplayVideo = false
        draft.includeSensorEvidence = false
        draft.uploadConsent = SocialUploadConsent()
        XCTAssertTrue(draft.canPublish)
    }

    func testConsentVersionMustMatchCurrentContract() {
        let oldConsent = SocialUploadConsent(
            version: "social-upload-consent-v0",
            accepted: true,
            acceptedAt: Date(timeIntervalSince1970: 1_755_000_000)
        )
        XCTAssertFalse(oldConsent.isValid(forReplayVideo: true, sensorEvidence: false))
        XCTAssertTrue(oldConsent.isValid(forReplayVideo: false, sensorEvidence: false))
    }

    func testSocialUserDerivesShortInitials() {
        let user = SocialUser(id: "u", handle: "rider", displayName: "Mara Rojas")
        XCTAssertEqual(user.initials, "MR")
    }

    func testPostContractRoundTripsThroughJSON() throws {
        let seed = SocialMockSeed.standard
        let post = try XCTUnwrap(seed.posts.first)
        let data = try JSONEncoder().encode(post)
        let decoded = try JSONDecoder().decode(SocialPost.self, from: data)
        XCTAssertEqual(decoded, post)
    }
}
