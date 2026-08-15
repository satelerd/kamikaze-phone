import Foundation
import Testing
@testable import Kamikaze

struct ExperienceCoordinatorTests {
    @MainActor
    @Test func runPhasesReduceToExperiencePhases() {
        #expect(NativeRunPhase.ready.experiencePhase == .idle)
        #expect(NativeRunPhase.armed.experiencePhase == .armed)
        #expect(NativeRunPhase.motion.experiencePhase == .motion)
        #expect(NativeRunPhase.settling.experiencePhase == .settling)
        #expect(NativeRunPhase.result.experiencePhase == .landed)
        #expect(NativeRunPhase.unknown.experiencePhase == .review)
        #expect(NativeRunPhase.failed("x").experiencePhase == .review)
    }

    @MainActor
    @Test func oneNoisySampleCannotFlashTheField() {
        let coordinator = ExperienceCoordinator()
        coordinator.reportMotion(gyroDps: ExperienceCoordinator.fullScaleGyroDps * 10)
        // A single report moves energy by at most one smoothing step.
        #expect(coordinator.state.motionEnergy <= ExperienceCoordinator.energySmoothing + 0.0001)
        #expect(coordinator.state.motionEnergy > 0)
    }

    @MainActor
    @Test func sustainedRotationConvergesToFullEnergy() {
        let coordinator = ExperienceCoordinator()
        for _ in 0 ..< 60 {
            coordinator.reportMotion(gyroDps: ExperienceCoordinator.fullScaleGyroDps)
        }
        #expect(coordinator.state.motionEnergy > 0.9)
        #expect(coordinator.state.motionEnergy <= 1)
    }

    @MainActor
    @Test func negativeAndAbsurdInputsStayClamped() {
        let coordinator = ExperienceCoordinator()
        coordinator.reportMotion(gyroDps: -500)
        #expect(coordinator.state.motionEnergy == 0)
        for _ in 0 ..< 200 {
            coordinator.reportMotion(gyroDps: 1_000_000)
        }
        #expect(coordinator.state.motionEnergy <= 1)
        coordinator.reportReplay(progress: 4)
        #expect(coordinator.state.replayProgress == 1)
        coordinator.reportReplay(progress: -1)
        #expect(coordinator.state.replayProgress == 0)
    }

    @MainActor
    @Test func returningToIdleResetsDerivedState() {
        let coordinator = ExperienceCoordinator()
        coordinator.report(phase: .motion)
        for _ in 0 ..< 10 {
            coordinator.reportMotion(gyroDps: 700)
        }
        coordinator.reportReplay(progress: 0.5)
        #expect(coordinator.state.motionEnergy > 0)

        coordinator.report(phase: .idle)
        #expect(coordinator.state.phase == .idle)
        #expect(coordinator.state.motionEnergy == 0)
        #expect(coordinator.state.replayProgress == 0)
    }
}
