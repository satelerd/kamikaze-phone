import Foundation
import Observation
import SwiftUI
import os

/// Game phase as the experience system sees it — the shared vocabulary from
/// NATIVE_EXPERIENCE_SYSTEM_V1. Visual layers consume this reduced state,
/// never the raw 100 Hz sensor stream.
nonisolated enum ExperiencePhase: String, Equatable, Sendable {
    case idle
    case armed
    case motion
    case settling
    case landed
    case review
    case replay

    /// Semantic palette: Ion for ready/live, Hazard for motion/review,
    /// Volt for resolution. Color is never the only state signal.
    @MainActor var accentColor: Color {
        switch self {
        case .idle, .armed: KamikazeTheme.ion
        case .motion, .settling, .review: KamikazeTheme.hazard
        case .landed: KamikazeTheme.volt
        case .replay: KamikazeTheme.ion
        }
    }
}

nonisolated struct ExperienceState: Equatable, Sendable {
    var phase: ExperiencePhase = .idle
    /// Smoothed, clamped rotation energy in 0...1. Noisy sensor values can
    /// never flash the screen because smoothing happens in the coordinator.
    var motionEnergy: Double = 0
    /// Deterministic playhead when `phase == .replay`.
    var replayProgress: Double = 0
    var reduceEffects: Bool = false
}

/// One reducer between gameplay and every visual layer. Producers report
/// phases and raw gyro magnitudes; consumers read an already-smoothed state
/// at a rendering-safe cadence.
@MainActor
@Observable
final class ExperienceCoordinator {
    /// Full-scale rotation: a violent trick peaks around 720°/s or more.
    static let fullScaleGyroDps: Double = 720
    /// Low-pass factor per report. High enough to feel live, low enough that
    /// a single noisy sample cannot jump the field.
    static let energySmoothing = 0.18

    private static let signposter = OSSignposter(
        subsystem: "tech.sateler.kamikazephone",
        category: "experience"
    )

    private(set) var state = ExperienceState()

    /// Resting accent requested by the frontmost screen while idle.
    private(set) var ambientAccent: Color?

    /// Debug kill switch for the whole field layer (Workshop / launch arg
    /// `-debugDisableField YES`), so an expensive layer can be isolated.
    var fieldDisabled = UserDefaults.standard.bool(forKey: "debugDisableField")

    func setAmbient(accent: Color?) {
        ambientAccent = accent
    }

    /// Effective field accent: the phase palette while a run is active, the
    /// frontmost screen's resting accent otherwise.
    func fieldAccent(ambient: Color?) -> Color {
        if state.phase == .idle {
            return ambient ?? ambientAccent ?? KamikazeTheme.ion
        }
        return state.phase.accentColor
    }

    func report(phase: ExperiencePhase) {
        guard state.phase != phase else { return }
        let previous = state.phase.rawValue
        Self.signposter.emitEvent("phase", "\(previous, privacy: .public) -> \(phase.rawValue, privacy: .public)")
        state.phase = phase
        if phase == .idle {
            state.motionEnergy = 0
            state.replayProgress = 0
        }
    }

    /// Raw gyro magnitude in degrees/second, from any live capture screen.
    func reportMotion(gyroDps: Double) {
        let clamped = min(1, max(0, gyroDps / Self.fullScaleGyroDps))
        let smoothed = state.motionEnergy * (1 - Self.energySmoothing) + clamped * Self.energySmoothing
        state.motionEnergy = min(1, max(0, smoothed))
    }

    func reportReplay(progress: Double) {
        state.replayProgress = min(1, max(0, progress))
    }

    func setReduceEffects(_ reduce: Bool) {
        state.reduceEffects = reduce
    }
}

/// The one field, as screens consume it: every instance reads the same
/// coordinator state and the same wall clock, so phase, energy and drift stay
/// continuous across tabs. TabView/NavigationStack paint opaque container
/// backgrounds, which is why the field lives at screen roots instead of one
/// layer physically below the tab hierarchy.
struct ExperienceFieldBackground: View {
    @Environment(ExperienceCoordinator.self) private var experience
    var ambient: Color?
    /// Tab stacks keep every screen alive; only the visible one may animate
    /// its field, or four fields burn frames for one viewport.
    @State private var isVisible = false

    var body: some View {
        Group {
            if experience.fieldDisabled {
                KamikazeTheme.pitch.ignoresSafeArea()
            } else {
                SlipstreamField(
                    accent: experience.fieldAccent(ambient: ambient),
                    energy: experience.state.reduceEffects ? 0 : experience.state.motionEnergy,
                    paused: !isVisible
                )
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
