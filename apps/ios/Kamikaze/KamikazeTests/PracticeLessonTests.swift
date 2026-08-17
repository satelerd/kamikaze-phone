import Testing
@testable import Kamikaze

struct PracticeLessonTests {
    @Test func lessonOrderMatchesThePlayerLoop() {
        #expect(PracticeLessonStep.learn.next == .follow)
        #expect(PracticeLessonStep.follow.next == .tryIt)
        #expect(PracticeLessonStep.tryIt.next == .review)
        #expect(PracticeLessonStep.review.next == nil)
    }

    @Test func tapeCompletionOnlyMarksEarlierSteps() {
        #expect(PracticeLessonStep.learn.isComplete(relativeTo: .follow))
        #expect(!PracticeLessonStep.follow.isComplete(relativeTo: .follow))
        #expect(!PracticeLessonStep.review.isComplete(relativeTo: .follow))
    }
}
