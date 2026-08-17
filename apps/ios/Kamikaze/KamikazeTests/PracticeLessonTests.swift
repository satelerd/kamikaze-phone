import Testing
import KamikazeMotionCore
@testable import Kamikaze

struct PracticeLessonTests {
    @Test func lessonOrderMatchesThePlayerLoop() {
        #expect(PracticeLessonStep.learn.next == .tryIt)
        #expect(PracticeLessonStep.tryIt.next == nil)
    }

    @Test func tapeCompletionOnlyMarksEarlierSteps() {
        #expect(PracticeLessonStep.learn.isComplete(relativeTo: .tryIt))
        #expect(!PracticeLessonStep.tryIt.isComplete(relativeTo: .tryIt))
    }

    @Test func practicePassesOnlyTheExactRecognizedTarget() {
        #expect(PracticeAttemptJudgement.isSuccess(
            target: .flip,
            automaticStatus: .recognized,
            automaticTrickID: .flip,
            humanReview: nil
        ))
        #expect(!PracticeAttemptJudgement.isSuccess(
            target: .flip,
            automaticStatus: .recognized,
            automaticTrickID: .phoneFlip,
            humanReview: nil
        ))
        #expect(!PracticeAttemptJudgement.isSuccess(
            target: .flip,
            automaticStatus: .review,
            automaticTrickID: .flip,
            humanReview: nil
        ))
    }

    @Test func humanPracticeFeedbackSupersedesTheDetector() {
        let notQuite = HumanAttemptReview(trickID: .flip, outcome: .missed)
        #expect(!PracticeAttemptJudgement.isSuccess(
            target: .flip,
            automaticStatus: .recognized,
            automaticTrickID: .flip,
            humanReview: notQuite
        ))

        let correction = HumanAttemptReview(trickID: .flip, outcome: .landed)
        #expect(PracticeAttemptJudgement.isSuccess(
            target: .flip,
            automaticStatus: .recognized,
            automaticTrickID: .phoneFlip,
            humanReview: correction
        ))
    }
}
