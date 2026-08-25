import Foundation
import Testing
@testable import Kamikaze

struct CommunityTrickWorkflowTests {
    private let creator = CommunityTrickActor(id: "creator-1")
    private let contributor = CommunityTrickActor(id: "rider-2")
    private let moderator = CommunityTrickActor(id: "moderator-1", role: .moderator)
    private let date = Date(timeIntervalSince1970: 1_788_192_000)

    @Test func creatorReviewsAnotherRidersExampleAndPromotesIt() async throws {
        let repository = MemoryCommunityTrickRepository()
        let workflow = CommunityTrickWorkflow(repository: repository)
        try await publishProposal(in: workflow)
        let example = try await workflow.addExample(
            proposalID: "trick-corkscrew",
            contributorID: contributor.id,
            evidence: evidence(attemptID: "attempt-1"),
            outcome: .landed,
            notes: "Clean catch",
            id: "example-1",
            at: date
        )
        _ = try await workflow.submitExample(exampleID: example.id, actor: contributor, at: date)
        let approved = try await workflow.reviewExample(
            exampleID: example.id,
            actor: creator,
            decision: .approved,
            reviewID: "review-example-1",
            at: date
        )

        #expect(approved.status == .approved)
        let records = try await workflow.trainingEvidence(proposalID: "trick-corkscrew")
        #expect(records.count == 1)
        #expect(records[0].exampleID == example.id)
        #expect(records[0].approvedByID == creator.id)
        #expect(records[0].trainingState == .eligibleForOfflineReview)
        #expect(records[0].detectorVersionAtPromotion == "detector-v0.2-frozen")
    }

    @Test func approvalBeforeProposalPublicationPromotesWhenModeratorPublishes() async throws {
        let repository = MemoryCommunityTrickRepository()
        let workflow = CommunityTrickWorkflow(repository: repository)
        _ = try await createAndSubmitProposal(in: workflow)
        let example = try await workflow.addExample(
            proposalID: "trick-corkscrew",
            contributorID: contributor.id,
            evidence: evidence(attemptID: "attempt-2"),
            outcome: .missed,
            id: "example-2",
            at: date
        )
        _ = try await workflow.submitExample(exampleID: example.id, actor: contributor, at: date)
        _ = try await workflow.reviewExample(
            exampleID: example.id,
            actor: creator,
            decision: .approved,
            reviewID: "review-example-2",
            at: date
        )
        #expect(try await workflow.trainingEvidence().isEmpty)

        _ = try await workflow.reviewProposal(
            proposalID: "trick-corkscrew",
            actor: moderator,
            decision: .approved,
            reviewID: "review-proposal-2",
            at: date
        )

        let records = try await workflow.trainingEvidence()
        #expect(records.count == 1)
        #expect(records[0].outcome == .missed)
    }

    @Test func rejectedAndUnclearExamplesNeverBecomeTrainingEvidence() async throws {
        let repository = MemoryCommunityTrickRepository()
        let workflow = CommunityTrickWorkflow(repository: repository)
        try await publishProposal(in: workflow)
        let rejected = try await workflow.addExample(
            proposalID: "trick-corkscrew",
            contributorID: contributor.id,
            evidence: evidence(attemptID: "attempt-rejected"),
            outcome: .landed,
            id: "example-rejected",
            at: date
        )
        _ = try await workflow.submitExample(exampleID: rejected.id, actor: contributor, at: date)
        _ = try await workflow.reviewExample(
            exampleID: rejected.id,
            actor: creator,
            decision: .rejected,
            notes: "This is a full shuvit, not the proposed motion.",
            reviewID: "review-rejected",
            at: date
        )

        let unclear = try await workflow.addExample(
            proposalID: "trick-corkscrew",
            contributorID: contributor.id,
            evidence: evidence(attemptID: "attempt-unclear"),
            outcome: .unclear,
            id: "example-unclear",
            at: date
        )
        await #expect(throws: CommunityTrickWorkflow.WorkflowError.invalidExample) {
            try await workflow.submitExample(exampleID: unclear.id, actor: contributor, at: date)
        }
        #expect(try await workflow.trainingEvidence().isEmpty)
    }

    @Test func creatorCannotApproveTheirOwnEvidenceWithoutModerator() async throws {
        let repository = MemoryCommunityTrickRepository()
        let workflow = CommunityTrickWorkflow(repository: repository)
        try await publishProposal(in: workflow)
        let example = try await workflow.addExample(
            proposalID: "trick-corkscrew",
            contributorID: creator.id,
            evidence: evidence(attemptID: "attempt-self"),
            outcome: .landed,
            id: "example-self",
            at: date
        )
        _ = try await workflow.submitExample(exampleID: example.id, actor: creator, at: date)

        await #expect(throws: CommunityTrickWorkflow.WorkflowError.creatorCannotSelfApproveEvidence) {
            try await workflow.reviewExample(
                exampleID: example.id,
                actor: creator,
                decision: .approved,
                at: date
            )
        }
        let approved = try await workflow.reviewExample(
            exampleID: example.id,
            actor: moderator,
            decision: .approved,
            reviewID: "review-self-independent",
            at: date
        )
        #expect(approved.status == .approved)
        #expect(try await workflow.trainingEvidence().count == 1)
    }

    @Test func fileRepositoryRoundTripsAndRejectsDuplicateEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CommunityTrickWorkflowTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = FileCommunityTrickRepository(rootDirectory: root)
        let workflow = CommunityTrickWorkflow(repository: repository)
        try await publishProposal(in: workflow)
        _ = try await workflow.addExample(
            proposalID: "trick-corkscrew",
            contributorID: contributor.id,
            evidence: evidence(attemptID: "attempt-persisted"),
            outcome: .landed,
            id: "example-persisted",
            at: date
        )
        await #expect(throws: CommunityTrickWorkflow.WorkflowError.duplicateEvidence) {
            try await workflow.addExample(
                proposalID: "trick-corkscrew",
                contributorID: "rider-3",
                evidence: evidence(attemptID: "attempt-persisted"),
                outcome: .missed,
                id: "example-duplicate",
                at: date
            )
        }

        let reloaded = CommunityTrickWorkflow(
            repository: FileCommunityTrickRepository(rootDirectory: root)
        )
        let snapshot = try await reloaded.snapshot()
        #expect(snapshot.proposals.count == 1)
        #expect(snapshot.examples.count == 1)
        #expect(snapshot.examples[0].evidence.checksum == String(repeating: "a", count: 64))
    }

    @Test func rejectedDefinitionAndExampleCanBeRevisedAndResubmitted() async throws {
        let repository = MemoryCommunityTrickRepository()
        let workflow = CommunityTrickWorkflow(repository: repository)
        _ = try await createAndSubmitProposal(in: workflow)
        _ = try await workflow.reviewProposal(
            proposalID: "trick-corkscrew",
            actor: moderator,
            decision: .rejected,
            notes: "Make the physical cue more specific.",
            reviewID: "proposal-rejection",
            at: date
        )
        let revisedProposal = try await workflow.reviseProposal(
            proposalID: "trick-corkscrew",
            actor: creator,
            name: "Corkscrew Flip",
            description: "A diagonal flip with simultaneous yaw.",
            coachingCue: "Lead with the top-right corner and catch screen-up.",
            aliases: ["Cork Flip"],
            at: date.addingTimeInterval(1)
        )
        #expect(revisedProposal.status == .draft)
        _ = try await workflow.submitProposal(
            proposalID: revisedProposal.id,
            actor: creator,
            at: date.addingTimeInterval(2)
        )
        _ = try await workflow.reviewProposal(
            proposalID: revisedProposal.id,
            actor: moderator,
            decision: .approved,
            reviewID: "proposal-approval",
            at: date.addingTimeInterval(3)
        )

        let example = try await workflow.addExample(
            proposalID: revisedProposal.id,
            contributorID: contributor.id,
            evidence: evidence(attemptID: "attempt-revision"),
            outcome: .landed,
            id: "example-revision",
            at: date
        )
        _ = try await workflow.submitExample(exampleID: example.id, actor: contributor, at: date)
        _ = try await workflow.reviewExample(
            exampleID: example.id,
            actor: creator,
            decision: .rejected,
            notes: "The catch was not clean.",
            reviewID: "example-rejection",
            at: date
        )
        let revisedExample = try await workflow.reviseExample(
            exampleID: example.id,
            actor: contributor,
            outcome: .missed,
            notes: "Relabelled as a failed attempt.",
            at: date.addingTimeInterval(4)
        )
        #expect(revisedExample.status == .draft)
        #expect(revisedExample.outcome == .missed)
        _ = try await workflow.submitExample(
            exampleID: revisedExample.id,
            actor: contributor,
            at: date.addingTimeInterval(5)
        )
        _ = try await workflow.reviewExample(
            exampleID: revisedExample.id,
            actor: creator,
            decision: .approved,
            reviewID: "example-approval",
            at: date.addingTimeInterval(6)
        )
        #expect(try await workflow.trainingEvidence().first?.outcome == .missed)
    }

    private func createAndSubmitProposal(
        in workflow: CommunityTrickWorkflow
    ) async throws -> CommunityTrickProposal {
        _ = try await workflow.createProposal(
            creatorID: creator.id,
            name: "  Corkscrew   Flip ",
            description: "Flip and yaw through a diagonal corkscrew path.",
            coachingCue: "Lead with one corner, then catch the screen flat.",
            aliases: ["Cork Flip", "cork flip", "Diagonal Phone Flip"],
            id: "trick-corkscrew",
            at: date
        )
        let submitted = try await workflow.submitProposal(
            proposalID: "trick-corkscrew",
            actor: creator,
            at: date
        )
        #expect(submitted.name == "Corkscrew Flip")
        #expect(submitted.aliases == ["Cork Flip", "Diagonal Phone Flip"])
        return submitted
    }

    private func publishProposal(in workflow: CommunityTrickWorkflow) async throws {
        _ = try await createAndSubmitProposal(in: workflow)
        let published = try await workflow.reviewProposal(
            proposalID: "trick-corkscrew",
            actor: moderator,
            decision: .approved,
            reviewID: "review-proposal-1",
            at: date
        )
        #expect(published.status == .published)
    }

    private func evidence(attemptID: String) -> CommunityMotionEvidenceReference {
        CommunityMotionEvidenceReference(
            attemptID: attemptID,
            localResourceID: "attempt/\(attemptID)/sensor-evidence",
            payloadSchemaVersion: 3,
            sampleCount: 120,
            checksum: String(repeating: "a", count: 64),
            detectorVersionAtCapture: "detector-v0.2-frozen"
        )
    }
}
