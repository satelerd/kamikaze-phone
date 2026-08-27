import Foundation

actor CommunityTrickWorkflow {
    enum WorkflowError: LocalizedError, Equatable {
        case invalidProposal
        case invalidExample
        case proposalNotFound
        case exampleNotFound
        case invalidTransition
        case unauthorized
        case creatorCannotSelfApproveEvidence
        case duplicateEvidence

        var errorDescription: String? {
            switch self {
            case .invalidProposal: "Complete the trick name, description and coaching cue first."
            case .invalidExample: "This example does not contain reviewable labelled evidence."
            case .proposalNotFound: "The proposed trick no longer exists."
            case .exampleNotFound: "The submitted example no longer exists."
            case .invalidTransition: "That action is not available in the trick's current state."
            case .unauthorized: "Only the trick creator or a moderator can do that."
            case .creatorCannotSelfApproveEvidence:
                "A creator's own capture needs an independent moderator review."
            case .duplicateEvidence: "This motion capture is already attached to the trick."
            }
        }
    }

    private let repository: any CommunityTrickRepository

    init(repository: any CommunityTrickRepository) {
        self.repository = repository
    }

    @discardableResult
    func createProposal(
        creatorID: String,
        name: String,
        description: String,
        coachingCue: String,
        aliases: [String] = [],
        id: String = UUID().uuidString.lowercased(),
        at date: Date = Date()
    ) async throws -> CommunityTrickProposal {
        let proposal = CommunityTrickProposal(
            id: id,
            creatorID: creatorID,
            name: name,
            description: description,
            coachingCue: coachingCue,
            aliases: aliases,
            createdAt: date
        )
        guard proposal.isValidDraft else { throw WorkflowError.invalidProposal }
        var snapshot = try await repository.load()
        guard !snapshot.proposals.contains(where: { $0.id == proposal.id }) else {
            throw WorkflowError.invalidProposal
        }
        snapshot.proposals.append(proposal)
        try await repository.save(snapshot)
        return proposal
    }

    @discardableResult
    func reviseProposal(
        proposalID: String,
        actor: CommunityTrickActor,
        name: String,
        description: String,
        coachingCue: String,
        aliases: [String] = [],
        at date: Date = Date()
    ) async throws -> CommunityTrickProposal {
        var snapshot = try await repository.load()
        let index = try proposalIndex(proposalID, in: snapshot)
        let current = snapshot.proposals[index]
        guard current.creatorID == actor.id else { throw WorkflowError.unauthorized }
        guard current.status == .draft || current.status == .rejected else {
            throw WorkflowError.invalidTransition
        }
        var revised = CommunityTrickProposal(
            id: current.id,
            creatorID: current.creatorID,
            name: name,
            description: description,
            coachingCue: coachingCue,
            aliases: aliases,
            status: .draft,
            createdAt: parseTimestamp(current.createdAtISO8601) ?? date
        )
        revised.updatedAtISO8601 = timestamp(date)
        guard revised.isValidDraft else { throw WorkflowError.invalidProposal }
        snapshot.proposals[index] = revised
        try await repository.save(snapshot)
        return revised
    }

    @discardableResult
    func submitProposal(
        proposalID: String,
        actor: CommunityTrickActor,
        at date: Date = Date()
    ) async throws -> CommunityTrickProposal {
        var snapshot = try await repository.load()
        let index = try proposalIndex(proposalID, in: snapshot)
        guard snapshot.proposals[index].creatorID == actor.id else { throw WorkflowError.unauthorized }
        guard snapshot.proposals[index].status == .draft || snapshot.proposals[index].status == .rejected else {
            throw WorkflowError.invalidTransition
        }
        snapshot.proposals[index].status = .submitted
        snapshot.proposals[index].updatedAtISO8601 = timestamp(date)
        try await repository.save(snapshot)
        return snapshot.proposals[index]
    }

    @discardableResult
    func reviewProposal(
        proposalID: String,
        actor: CommunityTrickActor,
        decision: CommunityReviewDecision,
        notes: String = "",
        reviewID: String = UUID().uuidString.lowercased(),
        at date: Date = Date()
    ) async throws -> CommunityTrickProposal {
        guard actor.role == .moderator else { throw WorkflowError.unauthorized }
        var snapshot = try await repository.load()
        let index = try proposalIndex(proposalID, in: snapshot)
        guard snapshot.proposals[index].status == .submitted else { throw WorkflowError.invalidTransition }
        snapshot.proposals[index].status = decision == .approved ? .published : .rejected
        snapshot.proposals[index].updatedAtISO8601 = timestamp(date)
        snapshot.proposalReviews.append(CommunityProposalReview(
            id: reviewID,
            proposalID: proposalID,
            reviewerID: actor.id,
            decision: decision,
            notes: notes.normalizedWorkflowText,
            reviewedAtISO8601: timestamp(date)
        ))
        if decision == .approved {
            promoteApprovedExamples(proposalID: proposalID, snapshot: &snapshot, at: date)
        }
        try await repository.save(snapshot)
        return snapshot.proposals[index]
    }

    @discardableResult
    func addExample(
        proposalID: String,
        contributorID: String,
        evidence: CommunityMotionEvidenceReference,
        outcome: CommunityTrickExampleOutcome,
        notes: String = "",
        id: String = UUID().uuidString.lowercased(),
        at date: Date = Date()
    ) async throws -> CommunityTrickExample {
        var snapshot = try await repository.load()
        let proposal = snapshot.proposals[try proposalIndex(proposalID, in: snapshot)]
        guard proposal.status == .submitted || proposal.status == .published else {
            throw WorkflowError.invalidTransition
        }
        guard !snapshot.examples.contains(where: {
            $0.proposalID == proposalID && $0.evidence.attemptID == evidence.attemptID
        }) else { throw WorkflowError.duplicateEvidence }
        let example = CommunityTrickExample(
            id: id,
            proposalID: proposalID,
            contributorID: contributorID,
            evidence: evidence,
            outcome: outcome,
            notes: notes,
            createdAt: date
        )
        guard example.isValid else { throw WorkflowError.invalidExample }
        snapshot.examples.append(example)
        try await repository.save(snapshot)
        return example
    }

    @discardableResult
    func reviseExample(
        exampleID: String,
        actor: CommunityTrickActor,
        outcome: CommunityTrickExampleOutcome,
        notes: String = "",
        at date: Date = Date()
    ) async throws -> CommunityTrickExample {
        var snapshot = try await repository.load()
        let index = try exampleIndex(exampleID, in: snapshot)
        guard snapshot.examples[index].contributorID == actor.id else { throw WorkflowError.unauthorized }
        guard snapshot.examples[index].status == .draft || snapshot.examples[index].status == .rejected else {
            throw WorkflowError.invalidTransition
        }
        snapshot.examples[index].outcome = outcome
        snapshot.examples[index].notes = notes.normalizedWorkflowText
        snapshot.examples[index].status = .draft
        snapshot.examples[index].updatedAtISO8601 = timestamp(date)
        guard snapshot.examples[index].isValid else { throw WorkflowError.invalidExample }
        try await repository.save(snapshot)
        return snapshot.examples[index]
    }

    @discardableResult
    func submitExample(
        exampleID: String,
        actor: CommunityTrickActor,
        at date: Date = Date()
    ) async throws -> CommunityTrickExample {
        var snapshot = try await repository.load()
        let index = try exampleIndex(exampleID, in: snapshot)
        let example = snapshot.examples[index]
        guard example.contributorID == actor.id else { throw WorkflowError.unauthorized }
        guard example.status == .draft || example.status == .rejected else {
            throw WorkflowError.invalidTransition
        }
        guard example.outcome.isReviewableEvidence else { throw WorkflowError.invalidExample }
        snapshot.examples[index].status = .submitted
        snapshot.examples[index].updatedAtISO8601 = timestamp(date)
        try await repository.save(snapshot)
        return snapshot.examples[index]
    }

    @discardableResult
    func reviewExample(
        exampleID: String,
        actor: CommunityTrickActor,
        decision: CommunityReviewDecision,
        notes: String = "",
        reviewID: String = UUID().uuidString.lowercased(),
        at date: Date = Date()
    ) async throws -> CommunityTrickExample {
        var snapshot = try await repository.load()
        let index = try exampleIndex(exampleID, in: snapshot)
        let example = snapshot.examples[index]
        let proposal = snapshot.proposals[try proposalIndex(example.proposalID, in: snapshot)]
        let isCreator = proposal.creatorID == actor.id
        guard isCreator || actor.role == .moderator else { throw WorkflowError.unauthorized }
        if isCreator, example.contributorID == actor.id, actor.role != .moderator {
            throw WorkflowError.creatorCannotSelfApproveEvidence
        }
        guard example.status == .submitted else { throw WorkflowError.invalidTransition }
        snapshot.examples[index].status = decision == .approved ? .approved : .rejected
        snapshot.examples[index].updatedAtISO8601 = timestamp(date)
        snapshot.exampleReviews.append(CommunityExampleReview(
            id: reviewID,
            exampleID: example.id,
            proposalID: proposal.id,
            reviewerID: actor.id,
            decision: decision,
            notes: notes.normalizedWorkflowText,
            reviewedAtISO8601: timestamp(date)
        ))
        if decision == .approved, proposal.status == .published {
            promote(example: snapshot.examples[index], reviewerID: actor.id, snapshot: &snapshot, at: date)
        }
        try await repository.save(snapshot)
        return snapshot.examples[index]
    }

    func snapshot() async throws -> CommunityTrickSnapshot {
        try await repository.load()
    }

    /// Exportable eligibility records only. This method does not update the
    /// detector, its catalog, or any runtime matcher state.
    func trainingEvidence(proposalID: String? = nil) async throws -> [CommunityTrainingEvidence] {
        let records = try await repository.load().trainingEvidence
        guard let proposalID else { return records }
        return records.filter { $0.proposalID == proposalID }
    }

    private func proposalIndex(
        _ id: String,
        in snapshot: CommunityTrickSnapshot
    ) throws -> Array<CommunityTrickProposal>.Index {
        guard let index = snapshot.proposals.firstIndex(where: { $0.id == id }) else {
            throw WorkflowError.proposalNotFound
        }
        return index
    }

    private func exampleIndex(
        _ id: String,
        in snapshot: CommunityTrickSnapshot
    ) throws -> Array<CommunityTrickExample>.Index {
        guard let index = snapshot.examples.firstIndex(where: { $0.id == id }) else {
            throw WorkflowError.exampleNotFound
        }
        return index
    }

    private func promoteApprovedExamples(
        proposalID: String,
        snapshot: inout CommunityTrickSnapshot,
        at date: Date
    ) {
        for example in snapshot.examples where example.proposalID == proposalID && example.status == .approved {
            guard let review = snapshot.exampleReviews.last(where: {
                $0.exampleID == example.id && $0.decision == .approved
            }) else { continue }
            promote(example: example, reviewerID: review.reviewerID, snapshot: &snapshot, at: date)
        }
    }

    private func promote(
        example: CommunityTrickExample,
        reviewerID: String,
        snapshot: inout CommunityTrickSnapshot,
        at date: Date
    ) {
        guard !snapshot.trainingEvidence.contains(where: { $0.exampleID == example.id }) else { return }
        snapshot.trainingEvidence.append(CommunityTrainingEvidence(
            schemaVersion: CommunityTrainingEvidence.schemaVersion,
            id: "training-\(example.id)",
            proposalID: example.proposalID,
            exampleID: example.id,
            evidence: example.evidence,
            outcome: example.outcome,
            contributorID: example.contributorID,
            approvedByID: reviewerID,
            approvedAtISO8601: timestamp(date),
            detectorVersionAtPromotion: example.evidence.detectorVersionAtCapture,
            trainingState: .eligibleForOfflineReview
        ))
    }

    private func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func parseTimestamp(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private extension String {
    nonisolated var normalizedWorkflowText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
