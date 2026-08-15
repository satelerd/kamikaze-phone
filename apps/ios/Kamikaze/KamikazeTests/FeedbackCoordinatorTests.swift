import CoreHaptics
import Foundation
import Testing
@testable import Kamikaze

struct FeedbackCoordinatorTests {
    /// The contamination gate: while the evidence window is active no cue may
    /// fire, regardless of user settings.
    @MainActor
    @Test func evidenceWindowBlocksEveryCue() {
        let saved = UserDefaults.standard.object(forKey: "feedbackHapticsEnabled")
        defer { restore(saved) }

        let coordinator = FeedbackCoordinator()
        coordinator.hapticsEnabled = true
        #expect(coordinator.policyAllows)

        coordinator.evidenceWindowActive = true
        #expect(!coordinator.policyAllows)

        coordinator.evidenceWindowActive = false
        #expect(coordinator.policyAllows)
    }

    @MainActor
    @Test func disablingHapticsPersistsAcrossInstances() {
        let saved = UserDefaults.standard.object(forKey: "feedbackHapticsEnabled")
        defer { restore(saved) }

        let coordinator = FeedbackCoordinator()
        coordinator.hapticsEnabled = false
        #expect(!coordinator.policyAllows)

        let reloaded = FeedbackCoordinator()
        #expect(!reloaded.hapticsEnabled)
    }

    @Test func everyAuthoredCueBuildsAValidPattern() throws {
        let cues: [FeedbackCue] = [
            .zeroed, .armed, .cancelled, .catchResolved,
            .landed(scoreBand: 0), .landed(scoreBand: 1), .landed(scoreBand: 2),
            .missed, .needsReview, .levelMastered, .cosmeticUnlocked,
        ]
        for cue in cues {
            let pattern = try FeedbackCoordinator.pattern(for: cue)
            // Restraint rule: every phrase resolves in under one second.
            #expect(pattern.duration < 1.0, "cue \(cue) is too long")
        }
    }

    @Test func landedComplexityGrowsWithScoreBandNeverBeyondBounds() throws {
        let low = try FeedbackCoordinator.pattern(for: .landed(scoreBand: 0))
        let high = try FeedbackCoordinator.pattern(for: .landed(scoreBand: 2))
        #expect(high.duration > low.duration)
        // Out-of-range bands clamp instead of crashing or escalating.
        let clamped = try FeedbackCoordinator.pattern(for: .landed(scoreBand: 99))
        #expect(clamped.duration == high.duration)
    }

    @MainActor
    private func restore(_ saved: Any?) {
        if let saved {
            UserDefaults.standard.set(saved, forKey: "feedbackHapticsEnabled")
        } else {
            UserDefaults.standard.removeObject(forKey: "feedbackHapticsEnabled")
        }
    }
}
