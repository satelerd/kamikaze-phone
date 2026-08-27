import KamikazeMotionCore
import Testing
@testable import Kamikaze

struct PlayModesTests {
    @Test func playModeCatalogIncludesContinuousLineAndCameraRun() {
        #expect(PlayMode.allCases == [.free, .line, .follow, .classic, .camera])
        #expect(PlayMode.line.detail.contains("Always listening"))
        #expect(PlayMode.camera.title == "CAMERA RUN")
    }

    @Test func lineSessionSumsRecognizedEventsAndRejectsDuplicateAttemptIDs() {
        var line = LineSessionState()
        line.record(LineTrickEvent(id: "a", trickName: "FLIP", points: 72, recognized: true))
        line.record(LineTrickEvent(id: "a", trickName: "FLIP", points: 72, recognized: true))
        line.record(LineTrickEvent(id: "b", trickName: "UNKNOWN THROW", points: 0, recognized: false))
        line.record(LineTrickEvent(id: "c", trickName: "SHUVIT", points: 81, recognized: true))

        #expect(line.attemptCount == 3)
        #expect(line.trickCount == 2)
        #expect(line.totalScore == 153)

        line.reset()
        #expect(line.events.isEmpty)
        #expect(line.totalScore == 0)
    }

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
