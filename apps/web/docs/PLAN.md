# KAMIKAZE PHONE — Full Game Plan

> From gyroscope experiment to a complete sensor-driven phone-throwing game.
> Target: one PR, reviewable by @satelerd, self-contained, no backend required.

## Vision

Kamikaze Phone becomes a *game console that is the controller*. You throw the phone;
every sensor it has (IMU, magnetometer, light, mic, battery, NFC, camera) becomes a
game mechanic. A radical 90s California surfer narrates your session. Every trick is
recorded, reconstructed in 3D, scored across style dimensions, and can unlock achievements.

## Goals and acceptance criteria

| ID | Goal | Acceptance criteria |
|----|------|---------------------|
| G1 | **Unified sensor engine, iOS + Android** | One `SensorEngine` streaming IMU at device rate on iOS Safari (permission flow) and Android Chrome (Pixel 9 reference). Capability detection per feature, never per platform. Simulator injection for desktop dev. |
| G2 | **Trajectory + trick engine (sensor fusion)** | Accelerometer AND gyro used: quaternion orientation integration, freefall detection from `|a| ≈ 0`, ballistic reconstruction (`h = g·T²/8`, launch velocity from windup integration), per-axis rotation totals. Trick classifier matches a trick library (flip / roll / helicopter / corkscrew / moonshot / zen toss, single→triple). Score is a breakdown: Amplitude, Rotation, Cleanliness, Catch, Commitment + grade S/A/B/C. Verified against synthetic throws (`npm run verify:physics`). |
| G3 | **Trick Lab: slow-mo video → 3D visualization** | High-FPS capture (front and/or back camera), exposure/motion-blur guidance, luminosity boost in post (WebGL filter). Three.js viewer: reconstructed trajectory curve with video frames projected on camera frusta along the path (nano-world-model `video_to_3d` style). Export bundle (frames + poses JSON) compatible with the DA3 point-cloud pipeline, documented in `docs/VIDEO-TO-3D.md`. |
| G4 | **Minigames + achievements** | Rail Grind (magnetometer detects metal rail), Fridge Surfer (MacBook/magnet surface via magnetometer), Eclipse (ambient light sensor: throw through darkness), Scream Meter (mic: hype scream multiplier + whoosh detection), Charger Bullseye (land on wireless charger, detected via Battery API), NFC Spots (claim skate-spots with NFC tags). Achievements store + gallery page. Each game playable where the sensor exists, visible-but-locked with an honest explanation where it does not. |
| G5 | **Hot Potato mode** | N players configurable, accelerating tick, voice narration of player names, throw/catch detection from IMU, elimination rounds, towel-wrap safety recommendation with pre-game animation. |
| G6 | **Coop mode** | Two-phone pairing (QR + WebRTC data channel, no backend) plus single-phone pass-around fallback. Coordination score: simultaneity of throws, matched airtime, combined style. |
| G7 | **Audio: ElevenLabs soundtrack + SFX** | `scripts/generate-audio.mjs` produces soundtrack + SFX via ElevenLabs Music/SFX APIs into `public/audio/` with a manifest. AudioBus with music/sfx/voice channels; procedural WebAudio fallback for every named sound so the game works with zero generated assets. Global mute. |
| G8 | **Surfer narrator (ElevenLabs agent, as-code)** | Agent config in `convai/` (elevenlabs CLI, freezeme pattern). 90s California surfer persona; receives live trick events as contextual updates and riffs on them. Mutable at all times; graceful degradation to scripted lines via TTS/speechSynthesis when offline or keyless. |
| G9 | **Free Ride mode** | Open session: you throw, the engine detects and reconstructs, the narrator watches the event stream and comments live (trajectory summaries, streaks, bails). More commentary than scoreboard. |
| G10 | **Haptic FX engine** | Flashlight (torch), vibration and SFX dynamically driven by game events: per-flip tick, grind rumble+flicker, catch slam+flash, countdown. Torch via `MediaStreamTrack.applyConstraints`, vibration via `navigator.vibrate`, screen-flash fallback where torch/vibration are unavailable (iOS web). |

## Compatibility policy (maximum, honest)

**Rule: gate by capability detection, never by user agent. Ship every feature even if only one platform supports it today.** Setup lets you pick your device (Pixel 9 / iPhone / other Android / desktop) to preset expectations, then live detection wins.

| Capability | Android Chrome (Pixel 9) | iOS Safari | Fallback |
|---|---|---|---|
| IMU (devicemotion) | ✅ | ✅ (permission prompt) | Simulator |
| Magnetometer | ✅ Generic Sensor API | ❌ no web API | Mode visible, locked, explains why |
| Ambient light | ✅ `AmbientLightSensor` | ❌ | Camera-luma estimate (experimental) |
| Torch | ✅ `applyConstraints({torch})` | ❌ | Full-screen white flash |
| Vibration | ✅ `navigator.vibrate` | ❌ | Audio transient + flash |
| Battery / charging | ✅ | ❌ | IMU stillness heuristic |
| Web NFC | ✅ | ❌ | QR-code spot markers |
| Mic / speech synthesis / camera / WebRTC | ✅ | ✅ | — |

## Architecture

```
src/lib/        types, capabilities, sensors, physics, sim, fx, audio, speech, store
src/modes/      one folder per game mode (registry in src/modes/index.ts, data-only)
src/app/        setup onboarding, home (mode grid), play/<mode> pages, achievements
convai/         ElevenLabs narrator agent as-code
scripts/        generate-audio.mjs, verify-physics.ts
docs/           PLAN.md (this), VIDEO-TO-3D.md
```

Core principle: modes consume the shared engines (`SensorEngine`, `ThrowTracker`, `FXEngine`, `AudioBus`, `Narrator`) and own only their UI + rules. The registry is data-only so modes never edit shared files.

## Verification

- `npm run verify:physics` — synthetic IMU throws (known airtime/spins) must classify correctly and reconstruct airtime within 5%.
- `npm run build` + `npm run lint` — clean.
- Desktop demo mode (simulated throws) exercises every screen without hardware.
- On-device checklist in the PR description (Pixel 9 + iPhone) for the parts only a hand and a towel can test.

## Out of scope (this PR)

- Server-side DA3 point-cloud reconstruction (export bundle + docs only).
- Native apps / app stores. Everything is installable as a PWA-style web app.
- Accounts/backend: all state is on-device (localStorage), coop is peer-to-peer.
