import AVFoundation
import CoreHaptics
import Foundation
import Observation

/// Semantic feedback moments. Views request cues; they never instantiate
/// generators or engines themselves.
nonisolated enum FeedbackCue: Equatable, Sendable {
    case zeroed
    case armed
    case cancelled
    case catchResolved
    case landed(scoreBand: Int)
    case missed
    case needsReview
    case levelMastered
    case cosmeticUnlocked
}

/// One interruption-safe feedback owner (X6): haptics through the Taptic
/// Engine, plus exactly TWO sounds — a minimal celebratory chime when a trick
/// is detected and a quiet falling tone when it is not. Nothing else makes
/// noise; per-cue foley was tried and rejected. Audio uses the ambient
/// category, so the silent switch and other apps' audio are respected.
///
/// Contamination rule: the Taptic Engine is visible to the accelerometer, so
/// while the evidence window is active NO cue plays, ever. That gate stays in
/// place until the physical contamination bench (stationary phone, 20 reps
/// per cue, baseline vs. peak comparison) proves specific cues safe.
@MainActor
@Observable
final class FeedbackCoordinator {
    private enum Key {
        static let haptics = "feedbackHapticsEnabled"
        static let sound = "feedbackSoundEnabled"
    }

    /// True from the moment capture is armed until the capture closes.
    /// Producers own this; every cue request while active is dropped.
    var evidenceWindowActive = false

    var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Key.haptics) }
    }

    var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: Key.sound) }
    }

    private var engine: CHHapticEngine?
    private var engineStarted = false
    private let supportsHaptics: Bool
    private var players: [String: AVAudioPlayer] = [:]
    private var audioSessionConfigured = false

    init() {
        hapticsEnabled = UserDefaults.standard.object(forKey: Key.haptics) as? Bool ?? true
        soundEnabled = UserDefaults.standard.object(forKey: Key.sound) as? Bool ?? true
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// The firing policy, independent of hardware: user setting plus the
    /// contamination gate. Hardware capability is applied on top.
    var policyAllows: Bool {
        hapticsEnabled && !evidenceWindowActive
    }

    func canPlay() -> Bool {
        policyAllows && supportsHaptics
    }

    func play(_ cue: FeedbackCue) {
        // The contamination gate covers BOTH senses: the speaker can reach
        // the sensors just like the Taptic Engine.
        guard !evidenceWindowActive else { return }
        if hapticsEnabled, supportsHaptics {
            do {
                try startEngineIfNeeded()
                if let engine {
                    let pattern = try Self.pattern(for: cue)
                    let player = try engine.makePlayer(with: pattern)
                    try player.start(atTime: CHHapticTimeImmediate)
                }
            } catch {
                // Unsupported or interrupted haptic hardware degrades
                // silently; visual state already carries the same meaning.
            }
        }
    }

    /// The only audible moment in the game: the detector resolving a throw.
    /// Success is a small rising glass chime; failure a quiet falling tone.
    func playDetectionSound(success: Bool) {
        guard !evidenceWindowActive, soundEnabled else { return }
        playSound(named: success ? "cue-success" : "cue-fail")
    }

    private func playSound(named name: String) {
        if !audioSessionConfigured {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            audioSessionConfigured = true
        }
        if players[name] == nil,
           let url = Bundle.main.url(forResource: name, withExtension: "wav") {
            players[name] = try? AVAudioPlayer(contentsOf: url)
            players[name]?.prepareToPlay()
        }
        guard let player = players[name] else { return }
        player.currentTime = 0
        player.play()
    }

    private func startEngineIfNeeded() throws {
        if engine == nil {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            // Interruption safety: recreate state instead of leaking a dead
            // engine after audio session interruptions or server restarts.
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor [weak self] in self?.engineStarted = false }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.engineStarted = false
                    try? self?.startEngineIfNeeded()
                }
            }
            self.engine = engine
        }
        if !engineStarted {
            try engine?.start()
            engineStarted = true
        }
    }

    // MARK: - Authored patterns

    /// Authored haptic phrases per the X6 cue restraint table. Everything is
    /// under a second; nothing repeats or buzzes.
    nonisolated static func pattern(for cue: FeedbackCue) throws -> CHHapticPattern {
        switch cue {
        case .zeroed:
            // Soft, short confirmation.
            return try transientPattern([(0, 0.45, 0.35)])
        case .armed:
            // One tight, precise tick.
            return try transientPattern([(0, 0.85, 0.9)])
        case .cancelled:
            // A low, neutral stop.
            return try transientPattern([(0, 0.4, 0.2)])
        case .catchResolved:
            // Sharp transient then a softer rebound after capture closure.
            return try transientPattern([(0, 1.0, 0.85), (0.12, 0.5, 0.4)])
        case let .landed(scoreBand):
            // Complexity, never loudness, reflects the band (0...2).
            let band = max(0, min(2, scoreBand))
            var events: [(TimeInterval, Float, Float)] = [(0, 0.9, 0.6), (0.11, 0.7, 0.5)]
            if band >= 1 { events.append((0.22, 0.8, 0.7)) }
            if band >= 2 { events.append((0.33, 1.0, 0.9)) }
            return try transientPattern(events)
        case .missed:
            // Low and nonpunitive.
            return try transientPattern([(0, 0.5, 0.15)])
        case .needsReview:
            return try transientPattern([(0, 0.45, 0.25), (0.14, 0.45, 0.25)])
        case .levelMastered:
            // The longest phrase, still under one second.
            return try transientPattern([
                (0, 0.7, 0.5), (0.12, 0.8, 0.6), (0.24, 0.9, 0.75), (0.42, 1.0, 0.9),
            ])
        case .cosmeticUnlocked:
            return try transientPattern([(0, 0.7, 0.6), (0.16, 0.9, 0.8)])
        }
    }

    private nonisolated static func transientPattern(
        _ events: [(time: TimeInterval, intensity: Float, sharpness: Float)]
    ) throws -> CHHapticPattern {
        try CHHapticPattern(
            events: events.map { event in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: event.intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: event.sharpness),
                    ],
                    relativeTime: event.time
                )
            },
            parameters: []
        )
    }
}
