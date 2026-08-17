import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct PlayModesTests {
    @Test func followDeckCoversEveryTrickAndConditionExactlyOnce() {
        #expect(FollowPromptDeck.prompts.count
            == FollowPromptDeck.tricks.count * FollowCondition.allCases.count)
        #expect(Set(FollowPromptDeck.prompts.map(\.id)).count == FollowPromptDeck.prompts.count)

        for trick in FollowPromptDeck.tricks {
            #expect(FollowPromptDeck.prompts.count { $0.trickID == trick }
                == FollowCondition.allCases.count)
        }
    }

    @Test func followEvidenceNoteRetainsPromptAndCondition() {
        let prompt = FollowPrompt(trickID: .doublePhoneFlip, condition: .fastLow)

        #expect(prompt.evidenceNote.contains("prompt=double-phone-flip"))
        #expect(prompt.evidenceNote.contains("condition=fastLow"))
    }

    @Test func shuffledDeckAvoidsImmediateRepeat() throws {
        let current = FollowPromptDeck.first
        let shuffled = FollowPromptDeck.shuffled(avoiding: current)

        #expect(try #require(shuffled.first) != current)
        #expect(Set(shuffled.map(\.id)) == Set(FollowPromptDeck.prompts.map(\.id)))
    }
}
