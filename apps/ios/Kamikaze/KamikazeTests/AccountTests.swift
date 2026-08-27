import XCTest
@testable import Kamikaze

final class AccountTests: XCTestCase {
    func testIdentityNormalizesDisplayNameAndDerivesInitials() {
        let identity = AccountIdentity(
            id: "u-1",
            displayName: "  Mara Rojas  ",
            emailAddress: "mara@example.com",
            isEmailVerified: true
        )

        XCTAssertEqual(identity.displayName, "Mara Rojas")
        XCTAssertEqual(identity.initials, "MR")
        XCTAssertEqual(identity.accessibilitySummary, "Mara Rojas, mara@example.com, email verified")
    }

    func testSignedOutSnapshotNeverCarriesAnIdentity() {
        XCTAssertEqual(AccountSnapshot.signedOut.phase, .signedOut)
        XCTAssertNil(AccountSnapshot.signedOut.identity)
        XCTAssertEqual(AccountSnapshot.signedOut.sync.state, .localOnly)
        XCTAssertFalse(AccountSnapshot.signedOut.canRequestDeletion)
    }

    func testSnapshotContractRoundTripsThroughJSON() throws {
        let snapshot = AccountSnapshot.previewSignedIn
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AccountSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
}

@MainActor
final class AccountSessionTests: XCTestCase {
    func testUnconfiguredSessionDoesNotPretendAppleSignInWorked() async {
        let session = UnconfiguredAccountSession()
        do {
            try await session.signInWithApple()
            XCTFail("Unconfigured Clerk should not create an identity")
        } catch let error as AccountSessionError {
            XCTAssertEqual(error, .clerkNotConfigured)
            XCTAssertEqual(session.snapshot.phase, .signedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockAuthKeepsExplicitRouteAndSupportsSignOut() async throws {
        let session = MockAccountSession()

        try await session.presentAuth(.signUp)
        XCTAssertEqual(session.lastRequestedAuthRoute, .signUp)
        XCTAssertEqual(session.snapshot.phase, .signedIn)

        try await session.signOut()
        XCTAssertEqual(session.snapshot, .signedOut)
    }

    func testViewModelPublishesConfigurationError() async {
        let model = AccountViewModel(session: UnconfiguredAccountSession())
        await model.signInWithApple()

        XCTAssertEqual(model.snapshot.phase, .signedOut)
        XCTAssertTrue(model.errorMessage?.contains("ACCOUNT SETUP NEEDED") == true)
        XCTAssertFalse(model.isWorking)
    }
}
