import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct OnboardingChallengeTests {
    @Test func straightAirRequiresFiftyEstimatedCentimeters() {
        #expect(!OnboardingChallengeEvaluator.passesStraightAir(estimatedHeightM: nil))
        #expect(!OnboardingChallengeEvaluator.passesStraightAir(estimatedHeightM: 0.499))
        #expect(OnboardingChallengeEvaluator.passesStraightAir(estimatedHeightM: 0.50))
        #expect(OnboardingChallengeEvaluator.passesStraightAir(estimatedHeightM: 0.64))
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

    @Test func flipRequiresTheExactRecognizedIdentity() {
        #expect(OnboardingChallengeEvaluator.passesFlip(
            status: .recognized,
            trickID: .flip
        ))
        #expect(!OnboardingChallengeEvaluator.passesFlip(
            status: .review,
            trickID: .flip
        ))
        #expect(!OnboardingChallengeEvaluator.passesFlip(
            status: .recognized,
            trickID: .doubleFlip
        ))
    }

    @Test func authoredStoryEndsWithLearnThenTry() {
        #expect(OnboardingStep.allCases == [
            .board, .safety, .origin, .straightAir, .shuvitLearn, .shuvitTry,
            .flipLearn, .flipTry,
        ])
    }
}
