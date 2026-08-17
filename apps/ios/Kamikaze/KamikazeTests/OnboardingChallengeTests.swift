import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct OnboardingChallengeTests {
    @Test func straightAirRequiresThirtyEstimatedCentimeters() {
        #expect(!OnboardingChallengeEvaluator.passesStraightAir(estimatedHeightM: nil))
        #expect(!OnboardingChallengeEvaluator.passesStraightAir(estimatedHeightM: 0.299))
        #expect(OnboardingChallengeEvaluator.passesStraightAir(estimatedHeightM: 0.30))
        #expect(OnboardingChallengeEvaluator.passesStraightAir(estimatedHeightM: 0.44))
    }

    @Test func shuvitRequiresTheExactRecognizedIdentity() {
        #expect(OnboardingChallengeEvaluator.passesShuvit(
            status: .recognized,
            trickID: .backsideShuvit
        ))
        #expect(!OnboardingChallengeEvaluator.passesShuvit(
            status: .review,
            trickID: .backsideShuvit
        ))
        #expect(!OnboardingChallengeEvaluator.passesShuvit(
            status: .recognized,
            trickID: .backsideThreeSixtyShuvit
        ))
    }

    @Test func authoredStoryEndsWithLearnThenTry() {
        #expect(OnboardingStep.allCases == [
            .board, .safety, .origin, .straightAir, .shuvitLearn, .shuvitTry,
        ])
    }
}
