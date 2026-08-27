import Testing
@testable import Kamikaze

@MainActor
struct CommunityTrickExchangeModelTests {
    @Test func draftMovesThroughMineReviewAndFieldSections() async {
        let repository = MemoryCommunityTrickRepository()
        let model = CommunityTrickExchangeModel(
            repository: repository,
            creatorID: "creator-ui"
        )

        let created = await model.create(
            name: "Corkscrew",
            description: "A diagonal flip with a simultaneous turn.",
            coachingCue: "Lead with the top-right corner.",
            aliases: ["Cork flip"]
        )

        #expect(created)
        #expect(model.section == .mine)
        #expect(model.myProposals.count == 1)
        #expect(model.myProposals[0].status == .draft)

        await model.submit(model.myProposals[0])
        #expect(model.reviewProposals.count == 1)
        #expect(model.myProposals[0].status == .submitted)

        await model.review(model.reviewProposals[0], decision: .approved)
        #expect(model.reviewProposals.isEmpty)
        #expect(model.fieldProposals.count == 1)
        #expect(model.fieldProposals[0].status == .published)
    }

    @Test func invalidDraftStaysVisibleAsAnActionableError() async {
        let model = CommunityTrickExchangeModel(
            repository: MemoryCommunityTrickRepository(),
            creatorID: "creator-ui"
        )

        let created = await model.create(
            name: "X",
            description: "",
            coachingCue: "",
            aliases: []
        )

        #expect(!created)
        #expect(model.myProposals.isEmpty)
        #expect(model.errorMessage == "Complete the trick name, description and coaching cue first.")
    }
}
