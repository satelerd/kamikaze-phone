# Kamikaze: Phone Flip — experience prototype

## Product thesis

Kamikaze turns a physical phone trick into a one-more-try score game. The screen has one primary job: make the phone feel recognized the instant it leaves and returns to the hand.

This prototype is intentionally local-first and single-player. It proves the flow and emotional feedback before accounts, a social graph, cloud sync, leaderboards or a production economy are introduced.

## Core loop

```text
READY → ARM → THROW → AIR → CATCH → IDENTIFY → SCORE → REPLAY → AGAIN
```

- `READY`: the live 3D phone mirrors orientation and confirms sensor health.
- `ARM`: the game watches for freefall or a fast low gyro burst.
- `AIR`: controls disappear; the Flux Halo and haptics communicate capture.
- `CATCH`: the detector preserves post-roll long enough to confirm the landing.
- `RESULT`: trick, score and replay appear together, without navigating elsewhere.
- `AGAIN`: one action arms the next attempt and preserves run momentum.

Manual capture remains a practice tool. While it records, the whole gameplay surface becomes the stop target; a small stop button is not acceptable while holding and moving the phone.

## Information architecture

Four primary destinations keep the game legible:

1. **Play** — the core session, result and immediate replay.
2. **Practice** — target tricks, guided reps and detailed replay.
3. **Locker** — phone skins and future unlock economy.
4. **Profile** — totals, records, activity calendar and recent attempts.

Calibration and raw sensor labs remain developer utilities, reachable from Profile in test builds, not primary game tabs.

## First-launch onboarding

Onboarding is brief, optional and replayable from Profile.

1. **Welcome** — establish the physical premise, not a feature list.
2. **Play safe** — use a case and throw over something soft; Kamikaze does not make a phone impact-safe.
3. **Make it move** — request motion permission in context, show the live phone, then enter a guided first attempt.

The first successful attempt completes onboarding more effectively than another instructional page.

## Visual system

### Palette

| Token | Value | Role |
| --- | --- | --- |
| Bone | `#F3F1EA` | daylight canvas |
| Pitch | `#10110F` | stage and type |
| Ion | `#5B73FF` | ready, sensor lock, selected |
| Hazard | `#FF603F` | air, impact and warning |
| Volt | `#D7FF4A` | landed score and streak |
| Frost | `#E9ECF8` | glass fallback and quiet fill |

### Type

- Archivo Black: trick names, scores and decisive moments.
- Space Grotesk: controls, instructions and navigation.
- IBM Plex Mono: time, Hz, sensor state and compact records only.

### Geometry

Rounded shapes replace the technical prototype's rigid boxes. Large surfaces use 28–36 pt corners, controls use capsules and small records use 18–22 pt corners. Sharp geometry is reserved for fleeting impact marks.

### Signature: Flux Halo

The phone is the avatar. It stays in the center of a circular landing zone and mirrors the measured quaternion. Concentric halo layers communicate state:

- quiet blue breath while ready;
- compressed pulse while armed;
- fast hazard-orange rotation in air;
- volt flash when landed;
- muted red fracture when an attempt is not recognized.

Liquid Glass belongs to floating controls and navigation. It should reveal moving color beneath it and react to touch; it should not become a generic glass card applied to every block.

The app background is a lightweight kinetic color field rather than a second permanent WebGL context. It changes with play state and gives native glass moving material to refract without competing with the phone renderer for battery or frame time.

All player-facing 3D scenes share the same interaction vocabulary: one finger orbits, two fingers pinch to zoom and **Reset View** restores the camera without changing sensor calibration. Replays add a draggable scrubber and 1×, 0.5× and 0.25× playback speeds.

Practice is a six-level path in the prototype: backside shuvit, frontside shuvit, Phone Flip, Reverse Phone Flip, front flip and back flip. One 55+ landing unlocks the next level; three reps marks mastery. This progression is derived from saved attempts so it cannot drift away from the evidence in the local history.

## Screen sketches

```text
PLAY                              RESULT
┌────────────────────────┐        ┌────────────────────────┐
│ KAMIKAZE: PHONE FLIP  4×│        │ LANDED            92  │
│                        │        │ PHONE FLIP             │
│      ╭──────────╮      │        │ ╭────────────────────╮ │
│      │ FLUX     │      │        │ │ measured 3D replay │ │
│      │  PHONE   │      │        │ ╰────────────────────╯ │
│      ╰──────────╯      │        │ 0.69s       +1 streak  │
│        READY / AIR      │        │ [ AGAIN ] [ SHARE ]    │
│  ╭──────────────────╮  │        └────────────────────────┘
│  │ START SESSION    │  │
│  ╰──────────────────╯  │
│  Play Practice Locker Me│
└────────────────────────┘
```

```text
PRACTICE                          PROFILE
┌────────────────────────┐        ┌────────────────────────┐
│ LEARN A TRICK           │        │ SAT / LEVEL 03         │
│ [Phone Flip] [Reverse]  │        │ 142 flips   12 best run│
│ ╭────────────────────╮ │        │ ▪▪▫▪▪▪▪ activity grid │
│ │ clean target replay│ │        │ PERSONAL BESTS         │
│ ╰────────────────────╯ │        │ Fastest / longest / 96 │
│ 0 / 3 clean reps        │        │ RECENT                  │
│ [ START GUIDED SET ]    │        │ Phone Flip       91 →  │
└────────────────────────┘        └────────────────────────┘
```

## Scoring prototype

The displayed score remains one number. Internally it combines:

- target rotation and direction;
- axis purity;
- motion duration relative to the learned trick window;
- catch stability.

Points are the sum of landed attempt scores. The prototype uses them to preview the locker economy, but unlock prices and progression are not production-balanced.

## Widget and system surface strategy

A Home Screen widget can show today's flips, streak and personal best. A WidgetKit control can offer a start action, but a widget cannot continuously own the gyroscope: the extension runs separately and is not continually active. The realistic start control deep-links into an armed Play session. Live Activities can later mirror an active session, but production widgets require a development build and a newer Expo/native phase; they are not part of the Expo Go prototype.

## Product risks to design early

- **Physical safety:** clear first-run warning, case recommendation, soft-surface language and no implication of device protection.
- **Detection fairness:** preserve raw evidence, confidence and detector version with each attempt; never silently rewrite records after model updates.
- **Orientation and grip:** right/left grip plus portrait/landscape conventions must become explicit player settings.
- **False positives:** a run needs a visible armed state and an easy cancel path.
- **Battery and heat:** 100 Hz motion plus continuous GL rendering should pause when Play is not visible.
- **Accessibility:** never encode state through color alone; respect reduced motion, reduced transparency and optional haptics.
- **Privacy:** motion remains local unless a player explicitly publishes a replay.
- **Recovery:** interrupted sessions and sensor permission failures must return to a safe, understandable Ready state.

## Prototype boundary

Included now: first-run flow, full-screen Play states, result/replay, Practice framing, Profile/activity grid, Locker concept, native glass where available and developer access to existing calibration.

Deferred: production account model, cloud sync, public posts, moderation, Game Center, true widget target, sound design, Core Haptics composition, anti-cheat and a balanced progression economy.
