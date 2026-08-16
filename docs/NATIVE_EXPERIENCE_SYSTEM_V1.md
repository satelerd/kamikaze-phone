# Native experience system v1

Status: product, audiovisual and implementation plan. This refines Section 8
of `DEVELOPMENT_MASTER_PLAN.md` and expands the phone customization direction
from `PROFILE_LOCKER_STATS_V1.md`. It is not an implementation claim.

## Design thesis

Kamikaze is a **motion instrument disguised as a game**. The phone is not an
icon inside the interface; it is the playable object. A measured throw should
leave one coherent signature across light, glass, motion, sound and touch.

The signature interaction is **Motion Echo**:

- while idle, the field is alive but quiet;
- arming pulls the field and controls inward;
- rotation energy opens angular light around the phone;
- catch resolves that energy into one visual pulse;
- Result and Replay reproduce a deterministic echo from the recorded attempt,
  rather than playing generic celebration effects.

This is the deliberate aesthetic risk. Everything else stays restrained. No
confetti, decorative particles, fake skate footage or constant neon noise.

## Current implementation audit

What is already valuable:

- `KineticBackground` uses a native 3 × 3 `MeshGradient` with slow motion;
- Play changes accent between idle and active states;
- iOS 26 calls real `glassEffect`, with an iOS 18–25 Material fallback;
- standard glass button styles are already wrapped behind one modifier;
- RealityKit live and replay scenes are functional and interactive;
- Reduce Motion and Reduce Transparency have an initial fallback.

What prevents it from feeling like a complete system:

- every glass surface renders independently; there is no
  `GlassEffectContainer`, identity or shape morphing between controls;
- every surface uses the same regular glass while custom borders and large
  shadows partially paint over the native material;
- `GlassSurfaceLevel` changes only border/shadow values, not the glass role;
- the background receives one accent color, not game phase, motion energy,
  direction, score or replay time;
- each screen owns a new animated background and timeline;
- MeshGradient, blurred circles and scan-line Canvas redraw together without a
  measured screen-level rendering budget;
- no audio or haptic experience exists yet;
- live and replay each duplicate a two-box phone mesh;
- the current customization preview is a rounded 2D rectangle, not the shared
  playable phone.

## One shared experience state

Visuals and feedback consume a small reduced state, never the raw 100 Hz stream:

```swift
ExperienceState {
    phase             // idle, zeroed, armed, motion, settling, result, replay
    accent            // semantic palette, not arbitrary screen color
    motionEnergy      // smoothed 0...1
    dominantAxis      // x, y, z or compound
    direction         // signed when evidence is reliable
    resultKind        // landed, missed, review, unknown
    replayProgress    // deterministic 0...1
    reduceEffects
}
```

`ExperienceCoordinator` publishes at a rendering-safe cadence. Capture and
classification remain independent; dropping a visual frame can never drop a
sensor sample.

### Phase vocabulary

| Phase | Field | Glass/control | Phone | Sound/haptic |
|---|---|---|---|---|
| Idle | slow Ion current | controls at rest | live pose | silent |
| Zeroed | field briefly aligns | Zero control contracts | reference snaps flat/screen-facing by context | soft confirmation |
| Armed | light pulls toward center | Start morphs into armed state | halo tightens | one precise ready cue |
| Motion | directional shear, Hazard energy | nonessential controls recede | live orientation remains hero | none until contamination is proven safe |
| Settling | energy narrows | stop/cancel remains reachable | catch ring approaches | silent |
| Landed | one Volt resolve pulse | result controls emerge | measured pose resolves | catch + success phrase |
| Missed/review | field loses saturation or splits | correction action appears | measured replay remains truthful | low, nonpunitive cue |
| Replay | recorded energy drives field by playhead | transport is one glass cluster | deterministic recorded pose | optional replay sonification |

Color is never the only state signal; geometry, labels and motion vocabulary
carry the same meaning.

## Liquid Glass system

Apple positions Liquid Glass as a functional layer floating above content, not
as a texture to place on every decorative rectangle. Native containers improve
rendering and allow neighboring glass shapes to blend and morph. The plan uses
glass more visibly while preserving that hierarchy.

### Roles

```swift
enum GlassRole {
    case navigation       // tab bar and compact persistent controls
    case primaryAction    // Start, Retry, Equip; selectively tinted
    case secondaryAction  // Zero, camera, filter, share
    case transport        // play, scrub, speed and replay tools as one cluster
    case instrumentHUD    // sparse live state/evidence
    case contentPanel     // larger reading surface, quiet regular glass
}
```

- **Navigation:** rely on native `TabView` behavior on iOS 26 and keep content
  extending beneath it. Never add an opaque backing plate.
- **Primary actions:** use prominent interactive glass with one semantic tint.
- **Tool clusters:** group related controls in one `GlassEffectContainer`; use
  `glassEffectID` and transitions so Start can morph into Stop/Cancel, and Play
  can morph into Pause instead of replacing a button abruptly.
- **Content panels:** use quieter regular glass only when it improves grouping.
  Passive text does not need an individual liquid capsule.
- **Clear glass:** reserve for bold controls above visually rich content where
  legibility survives; regular glass is the default.
- **Fallback:** one `MaterialSurface` implementation for iOS 18–25, Increase
  Contrast and Reduce Transparency. Feature views do not branch on OS version.

Refactor `GlassSurface` into role-based configuration. Remove decorative border
and shadow layers where native glass already provides separation; retain only a
tested fallback treatment. Tinting all glass is explicitly prohibited because
it destroys action hierarchy.

### Glass acceptance

- iOS 26 diagnostics state `NATIVE GLASS`, never infer it from appearance;
- each control cluster owns one container and stable effect IDs;
- touch targets remain at least 44 × 44 points;
- tab content remains visible beneath the system glass bar;
- Increased Contrast, Reduce Transparency and light/dark adaptation remain
  legible;
- no screenshot is accepted as proof of smoothness: profile on device.

Apple references:

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)

## Dynamic background: Slipstream Field v2

Keep MeshGradient as the dependable base and add one restrained SwiftUI Metal
shader only if device profiling supports it. The shader produces slow refraction
and directional flow, not a screensaver.

Architecture:

```text
ExperienceState
      ↓ smoothed parameters (15–30 Hz)
SlipstreamFieldCoordinator
      ├── MeshGradient color/depth layer
      ├── optional stitchable Metal flow layer
      ├── Flux Halo around the phone
      └── vignette/legibility layer
```

- one field instance lives at the app shell instead of restarting per tab;
- screens request a palette/phase but do not create render loops;
- idle may update at 15–30 FPS; active/replay may request display cadence;
- phase transitions interpolate parameters instead of replacing backgrounds;
- motion input is low-pass filtered and clamped so noisy sensor values never
  flash the screen;
- replay derives the same field deterministically from recorded features and
  playhead;
- background pauses when covered/offscreen and becomes static under Reduce
  Motion or Low Power fallback;
- the shader can be disabled without changing information hierarchy.

The current color behavior remains: Ion for ready, Hazard for motion, Volt for
resolution. V2 adds shape and energy semantics rather than replacing a palette
that already works.

Native foundations:

- [MeshGradient](https://developer.apple.com/documentation/swiftui/meshgradient)
- [ShaderLibrary](https://developer.apple.com/documentation/swiftui/shaderlibrary)

## Motion and transition language

Use four timing tokens rather than arbitrary animations in every view:

| Token | Intent | Typical duration |
|---|---|---|
| `contact` | pressed, selected, zeroed | 90–140 ms |
| `response` | state/control change | 180–260 ms |
| `resolve` | catch to result hierarchy | 380–520 ms |
| `signature` | mastery/unlock/Motion Echo | 650–900 ms |

Important choreography:

1. **Start:** the CTA compresses and morphs into the armed indicator; the field
   pulls inward and the phone stays visually stable.
2. **Throw:** labels and secondary actions recede; the phone and its halo own
   the frame. No UI element follows raw samples directly except the live pose.
3. **Catch:** after capture closure, one shock ring resolves and the trick name
   enters before secondary statistics.
4. **Result:** identity → execution/score → replay transport, in that order.
5. **Retry:** the result glass cluster morphs back into Start without replacing
   the entire screen hierarchy.
6. **Unlock:** one Motion Echo from the mastered attempt writes the new item into
   Setup; no generic confetti.

Interactive orbit and scrub remain under the finger with no ornamental spring.
Reduce Motion uses fades, emphasis and static end states instead of removing
feedback entirely.

## Audio and haptic language

The sound world is **kinetic electronic foley**: tension, air, glass and a clean
mechanical catch. Avoid sampled skateboard wheels/ollies; they make the phone
feel like an imitation skateboard instead of its own game.

### One feedback coordinator

```swift
enum FeedbackCue {
    case zeroed, armed, cancelled
    case catchResolved
    case landed(scoreBand: Int)
    case missed, needsReview
    case levelMastered, cosmeticUnlocked
}
```

`FeedbackCoordinator` owns one audio session, a `CHHapticEngine`, preloaded AHAP
patterns and the short audio players. It handles interruption, suspension and
engine reset; feature views request semantic cues and never instantiate their
own generators.

- Core Haptics/AHAP supplies precisely synchronized authored haptic phrases;
- `AVAudioEngine`/preloaded player nodes handle richer short sounds and an
  optional low ambient bed;
- use `.ambient` behavior so player audio mixes appropriately and the silent
  switch is respected;
- Sound, Haptics and Reduced Effects are independent settings;
- unsupported haptic hardware degrades to visual/audio feedback without error.

Apple documents that Core Haptics supports transient/continuous events,
intensity/sharpness and synchronized custom audio, while engine stop/reset must
be handled explicitly:

- [Core Haptics](https://developer.apple.com/documentation/corehaptics)
- [Preparing an app to play haptics](https://developer.apple.com/documentation/corehaptics/preparing-your-app-to-play-haptics)
- [AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine)

### Cue restraint

- **Zero:** soft short confirmation.
- **Armed:** one tight, precise tick—never a repeating vibration.
- **During evidence capture:** no haptic by default. The Taptic Engine can be
  sensed by the accelerometer, and the player cannot feel it while airborne.
- **Catch:** a sharp transient followed by a softer rebound, only after capture
  closure.
- **Landed:** a short tonal resolve whose complexity can reflect score band,
  never loudness alone.
- **Missed/review:** a low neutral stop, not a punishment buzzer.
- **Mastery/unlock:** the longest phrase, still under one second.

Before enabling any sound or haptic while sampling, run a contamination bench:
stationary phone, 20 repetitions per cue, comparing gyro/acceleration baseline,
peak and segmentation false triggers. Any measurable trigger risk moves that
cue outside the evidence window.

Audio assets must be original, short, normalized and bundled locally. The first
sound kit is six cues, not a soundtrack. Replay sonification comes later and is
derived from stored motion, never played as if it were recorded audio.

## Phone customization: working name “Setup”

`Locker` remains the internal feature/folder name for now. It suggests storage,
while the actual job is constructing the phone you play with. Candidate labels:

| Name | Strength | Risk |
|---|---|---|
| **Setup** | real skate vocabulary; means the complete configured object | slightly technical without the 3D hero |
| Build | active and understandable | generic game language |
| Deck | strong skate association | implies only the surface graphic |
| Phone Lab | clearly editable | conflicts with Sensor/Trick Lab |
| Locker | familiar cosmetic inventory | passive storage, not creation |

Recommendation: prototype the player-facing tab as **Setup** before permanently
renaming routes, analytics or source folders.

### Phone Studio model

Replace the duplicated boxes with one shared `PhoneModelFactory` and authored
RealityKit assets:

```swift
PhoneAppearance {
    formFactor       // compact, standard, plus, pro/max
    bodyFinish       // anodized, brushed, matte, translucent...
    bodyColor
    edgeFinish
    caseStyle        // none, bumper, clear, rugged, graphic shell
    caseColor
    screenTheme      // emissive animated material
    mark             // decal/badge/scuff layer
    trailStyle       // replay/gameplay only
}
```

The visual model may offer recognizable recent iPhone proportions and camera
layouts, starting with the reference iPhone 15 Plus. Internal geometry uses a
versioned `DeviceShapeDefinition`; gameplay math never changes when the player
selects a larger or smaller cosmetic model.

Quality ladder:

1. **Shared shell:** accurate proportions, bevels, separate screen/glass/frame,
   camera island/lenses, buttons and a correct center-of-rotation pivot.
2. **Form factors:** Compact, Standard, Plus and Pro/Max silhouette families;
   select the current device by default when known.
3. **Materials:** `PhysicallyBasedMaterial` for glass, metal, clearcoat,
   roughness and emissive screen; authored lighting that works in every scene.
4. **Cases and marks:** interchangeable child meshes/material slots; decals use
   texture/UV slots rather than rebuilding geometry.
5. **Motion identity:** trail and screen shader reuse Motion Echo and respect
   Reduce Motion.

Load assets asynchronously, cache mesh/material resources and mutate material
parameters instead of recreating the entity tree per frame. Use a flattened
asset only when parts do not need independent customization. Apple supports USD
and Reality assets and recommends asynchronous loading/resource reuse for
RealityKit performance:

- [Loading entities from a file](https://developer.apple.com/documentation/realitykit/loading-entities-from-a-file)
- [RealityKit materials and shaders](https://developer.apple.com/documentation/realitykit/scene-content-materials-and-shaders)
- [Reducing RealityKit CPU utilization](https://developer.apple.com/documentation/realitykit/reducing-cpu-utilization-in-your-realitykit-app)

### Setup interaction

- interactive phone occupies at least the upper half of the screen;
- drag orbits, pinch zooms, Reset Camera restores the authored showcase view;
- category rail selects Model, Body, Case, Screen, Mark and Trail;
- tapping a choice previews it immediately everywhere through `AppearanceStore`;
- `Equip` commits; backing out restores the previously equipped appearance;
- locked choices show one concrete unlock condition, never only a padlock;
- compare mode holds before/after while pressing, without duplicate phone scenes.

## Performance and accessibility budget

Measure on the iPhone 15 Plus and at least one older/compact supported device.

- Play and interactive Setup target sustained display cadence with no visible
  input lag; for 60 Hz reference hardware, target 55+ rendered FPS.
- Apple describes ≤10 ms/s hitch rate as good; use that as the acceptance target
  for Start, catch/result, replay scrub and Setup orbit.
- profile with SwiftUI and Animation Hitches Instruments; track field, glass and
  RealityKit costs separately using signposts;
- add Debug toggles for field base, shader, halo, glass and audio/haptics so an
  expensive layer can be isolated;
- no raw motion integration, file I/O, entity loading or audio decoding occurs
  in `body` or the render update;
- pause field/scene work offscreen and preload the active phone before gameplay;
- test Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver,
  Dynamic Type, silent mode and haptic-unavailable behavior.

References:

- [Understanding hitches](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app)
- [SwiftUI performance analysis](https://developer.apple.com/documentation/swiftui/performance-analysis)

## Delivery slices

### X1 — experience contract and instrumentation

- add `ExperienceState`, semantic tokens and state-transition tests;
- add signposts and layer toggles before visual expansion;
- record baseline hitch/frame/energy traces on reference device;
- run audio/haptic sensor-contamination benchmark.

### X2 — real glass hierarchy

- refactor `GlassSurface` into roles and one OS fallback boundary;
- introduce containers, stable IDs and purposeful morphs;
- fix navigation/content-under-glass composition;
- validate iOS 26, iOS 18 fallback and accessibility variants.

### X3 — Slipstream Field v2

- move one field to the app shell;
- drive it from phase and smoothed motion energy;
- add the optional stitchable shader behind a feature flag;
- deterministic replay field and Reduce Motion/Low Power modes.

### X4 — Phone Studio and Setup prototype

- create shared phone factory and one high-quality iPhone 15 Plus-class asset;
- make live/replay/target/Setup consume the same model contract;
- add form-factor and Body/Case/Screen customization slots;
- prototype `Setup` label without renaming internal storage yet.

### X5 — choreography

- Start → Armed, catch → Result, Retry and Unlock sequences;
- stable glass identities and state-driven field/halo transitions;
- reduced-motion equivalents and interruption recovery.

### X6 — feedback engine

- one interruption-safe coordinator and settings;
- author six original sound/AHAP cues;
- enable only cues that pass the contamination gate;
- physical-device tuning for intensity, sharpness, mix and latency.

### X7 — integration and acceptance

- apply the same system to Play, Result, Replay, Practice, Profile and Setup;
- remove legacy per-screen effects and duplicated phone builders;
- performance, accessibility, battery and thermal run;
- physical taste test: normal play with sound/haptics on and off.

## Acceptance gates

- a blind screen recording makes Ready, Armed, Motion, Catch and Result visually
  distinguishable without diagnostic text;
- glass controls are visibly native and morph coherently on iOS 26;
- the background enriches refraction without competing with the phone or type;
- every animated layer is driven by one experience state and can be disabled;
- audio/haptics never alter segmentation or classifier evidence;
- all feedback survives interruption/background recovery without leaking an
  engine or playing late cues;
- the same configured phone appears in live, replay, target, history and Setup;
- Setup supports at least two form factors and three meaningful customization
  categories before claiming the editor is complete;
- reference device meets frame/hitch targets with all effects enabled;
- accessibility modes preserve state meaning and primary actions.

## Explicitly deferred

- procedural music or a continuous soundtrack;
- audio during flight before contamination testing;
- user-imported textures and moderation/storage implications;
- exact catalog of every historical iPhone;
- downloadable cosmetic assets, remote store and real-money purchases;
- spatial audio that provides no gameplay value on the phone speaker.

