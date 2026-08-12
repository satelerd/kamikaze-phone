# Kamikaze: Phone Flip — native iOS migration plan

Status: implementation-ready plan. The native rewrite has not started.

The Expo game prototype is frozen at Git tag `expo-game-v0.3.0`. It remains the behavioral and visual reference while the official iOS app is built beside it.

## Decision

Build the official app as a native SwiftUI application. Do not translate the React Native component tree line by line.

The migration is a controlled rewrite around four stable contracts:

1. recorded motion data;
2. attempt segmentation and trick scoring;
3. replay orientation and camera behavior;
4. the player journey from onboarding through Play, Result and Recent.

The recommended initial deployment target is iOS 18, compiled with Xcode 26. Native Liquid Glass is enabled on iOS 26 and newer; older supported systems receive a deliberate Material-based fallback. Revisit the deployment target before the first public TestFlight if supporting iOS 18 no longer matters.

## Product boundary for the first native version

The first native version is not feature-complete. It proves one excellent vertical slice:

```text
ONBOARDING -> READY -> ARMED -> THROW -> CATCH -> RESULT -> REPLAY -> AGAIN
```

It includes:

- first-launch onboarding and motion permission;
- a live 3D phone and clear Ready, Armed, Air and Landed states;
- automatic and manual capture;
- Phone Flip, Reverse Phone Flip, both shuvits, Front Flip and Back Flip;
- one score, confidence/unknown handling and detector versioning;
- replay Play/Pause, scrubbing, speed, orbit, pinch, Reset Camera and Zero Pose;
- local attempt history and a detailed Result/Recent screen;
- developer-only access to express and full calibration.

It deliberately defers the polished Practice progression, social publishing, accounts, cloud sync, the locker economy, widgets, lines and machine learning. Those features use the same foundations after Play is trustworthy.

## Repository layout

Keep the reference and native applications in the same repository until parity is proven:

```text
kamikaze-phone/
  mobile/                         # frozen Expo reference and data exporter
  native/
    Kamikaze.xcodeproj
    KamikazeApp/
      App/
      DesignSystem/
      Features/
        Onboarding/
        Play/
        Result/
        History/
        Practice/
        Locker/
        Profile/
        Workshop/
      Rendering/
      Persistence/
      Resources/
    Packages/
      KamikazeMotionCore/         # pure Swift, no SwiftUI/Core Motion imports
      KamikazeMotionApple/        # Core Motion adapter
    KamikazeTests/
    KamikazeUITests/
  fixtures/
    motion/v2/                    # shared, labelled JSON captures
  docs/
```

`KamikazeMotionCore` must build and test with Swift Package Manager. This makes the detector reproducible without launching Xcode or a phone.

## Architecture

Use SwiftUI's observation and environment patterns with feature-owned state. Do not create one view model per screen by habit.

```text
CMMotionManager
      |
      v
MotionCaptureActor -----> raw sample file
      |
      v
AttemptSegmenter -> FeatureExtractor -> TrickMatcher -> AttemptResult
      |                                      |
      +------------ ReplayBuilder <----------+
                             |
                             v
                   Play / Result / Practice
                             |
                             v
                SwiftData metadata repository
```

### Dependency boundaries

- `MotionSampleSource`: real Core Motion stream or deterministic fixture stream.
- `AttemptRepository`: saves metadata and resolves the raw sample file.
- `TrickCatalogRepository`: built-in and user-labelled trick definitions.
- `HapticClient`: Core Haptics in production, no-op in tests.
- `GameClock`: continuous clock in production, controllable clock in tests.
- `ReplayRenderer`: live, target and recorded scenes use one rendering implementation.

App services are injected through SwiftUI's environment. Feature state uses `@Observable` only when multiple views need shared mutable state; local interaction remains `@State`.

## Native motion data contract

The current schema is `DetectedAttempt.schemaVersion = 2`. Native work begins with schema 3 instead of silently changing its meaning.

Each native sample should contain:

- monotonic Core Motion timestamp;
- raw rotation rate in radians per second;
- user acceleration and gravity separately;
- acceleration including gravity derived explicitly when needed;
- Core Motion attitude quaternion;
- the logical body-frame vector after calibration;
- flags for missing or late data.

Each attempt should preserve:

- capture, trigger and detector versions;
- device model and OS version;
- requested and measured sample frequency;
- grip hand, screen orientation and calibration-profile ID;
- release, motion-start, motion-end, catch and settled timestamps;
- integrated signed rotations and total angular path;
- peak angular speed, catch impulse and stability;
- proposed trick, alternatives, confidence and optional player correction;
- immutable raw-sample file reference.

Store units in the native units at the boundary: seconds, radians/second and g. Convert to degrees only for player-facing values and compatibility fixtures.

### Two orientation paths are required

Use Core Motion's fused attitude for the stable live phone and relative replay orientation:

```text
q_relative(t) = inverse(q_start) * q_attitude(t)
```

Also integrate unbiased rotation rate for rotation count and direction:

```text
q_integrated(k+1) = normalize(q_integrated(k) * exp(0.5 * omega(k) * dt))
```

The fused attitude alone cannot prove that a phone completed one or more full rotations when its final orientation resembles its start. The gyro integral alone drifts. Keeping both lets the app cross-check them and exposes sensor quality instead of hiding it.

## Motion capture and concurrency

Own one `CMMotionManager` inside `MotionCaptureActor`. Deliver updates on a dedicated operation queue and immediately convert Apple types to Sendable value types.

- Request 100 Hz but always calculate the real interval from sample timestamps.
- Reject or mark non-monotonic, stale and implausibly large intervals.
- Never do UI work in the sensor callback.
- Feed every valid sample to the detector; publish display state at 30 or 60 Hz.
- Stop Core Motion whenever Play/Calibration is inactive or the app backgrounds.
- Use `.xArbitraryZVertical` initially; it gives a stable vertical without magnetometer dependence.
- Reset the relative attitude at Zero Pose without rewriting physical calibration.

The Simulator uses `FixtureMotionSource`; real sensor acceptance tests run on Daniel's iPhone. UI development must never require physically throwing the device.

## Detection pipeline

Separate segmentation from classification. A bad trick label must not change where the recorded window begins or ends.

### 1. Segment

Retain the existing dual trigger as the parity baseline:

- low-g/freefall trigger for higher throws;
- gyro-burst trigger for low, fast tricks;
- pre-roll before the trigger;
- dynamic motion end plus post-roll;
- catch and settled events when evidence exists;
- bounded timeout and cancellation.

The native detector produces explicit timestamps for `motionStart` and `motionEnd`. Replay uses those boundaries plus configurable handles, rather than pretending airtime and trick duration are identical.

### 2. Extract features

- signed angle and angular path per axis;
- dominant-axis energy and cross-axis coupling;
- direction changes;
- normalized angular-velocity curves;
- duration, time to peak and peak speed;
- low-g duration, catch impulse and post-catch stability;
- fused-attitude versus integrated-gyro disagreement;
- landing-face error relative to the calibrated start pose.

### 3. Match

Ship transparent rules first, but return the top three candidates and an Unknown result. A wrong confident name is worse than asking the player.

Then add labelled templates using time-normalized correlation or dynamic time warping. Only consider an on-device Core ML classifier after the dataset covers different speeds, cases, hands, devices, successful tricks and misses.

### 4. Score

Keep one player-facing score. Internally preserve components for debugging:

- rotation completeness and direction;
- axis purity;
- landing orientation and stability;
- timing only when the trick definition has enough real examples.

Calibration data and trick labels are evidence. Never retroactively overwrite a saved result when the detector changes; re-analysis creates a new analysis version.

## Calibration

Native Core Motion has a documented and stable device coordinate system, so the Expo platform-axis remapping should not be copied blindly.

Two flows remain useful:

- **Express calibration:** Zero Pose, right/left grip, short guided rotations with a ghost phone and immediate validation.
- **Full calibration:** positive/negative 90 and 360 degree rotations around every axis, variable tempo, saved captures and side-by-side target/measured replay.

The profile stores gyro bias, gain, sign, cross-talk/confidence, device identity and date. Axis permutation is supported as a diagnostic, not assumed as a normal requirement.

## 3D and replay

Use one reusable `PhoneSceneView` built with RealityKit `RealityView`:

- `live(attitude)`;
- `replay(frames, playhead)`;
- `target(definition, playhead)`;
- `comparison(measured, target)`;
- `locker(skin)`.

The scene owns the model, lights, floor and camera. Feature screens own only mode and controls.

- One-finger drag orbits the camera.
- Pinch changes a bounded camera distance.
- Reset Camera restores the mode's spectator/POV preset.
- Zero Pose changes the sensor reference only.
- Replay uses a `ContinuousClock`/display-linked playhead and samples frames by timestamp with quaternion slerp.
- Gesture precedence must keep 3D drags from scrolling the parent view.
- Live and replay updates are paused when offscreen.

Do not fabricate vertical translation from raw accelerometer double integration. A clearly labelled estimated ballistic arc can be added to freefall throws; otherwise orientation stays truthful and position remains anchored.

## Visual system and Liquid Glass

Preserve the Flux Halo, kinetic color field, bold type hierarchy and phone-as-avatar idea. Rebuild the layout natively instead of reproducing every pixel.

Create one design-system abstraction for glass:

- iOS 26+: `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` and `.glassProminent`;
- iOS 18–25: system Material, subtle stroke, tint and shadow fallback;
- Reduced Transparency: opaque high-contrast surface;
- Reduced Motion: state changes without large transforms.

Use Liquid Glass for the bottom navigation, primary floating action, replay controls and compact overlays. Do not cover every card with glass. Limit simultaneous glass containers and measure them with Instruments.

The backdrop starts with native `MeshGradient` and state-driven animation. A custom Metal shader is a later visual enhancement, not a prerequisite for the motion loop.

## Persistence

Use SwiftData for indexed metadata such as attempts, trick definitions, profiles, skins and preferences. Store sample arrays as versioned files under Application Support rather than a large SwiftData attribute.

Recommended file strategy:

- binary property list or compact binary Codable payload for normal local storage;
- JSON schema for export, fixtures and cross-language tests;
- atomic write to a temporary file, then rename;
- checksum and schema version on every payload;
- deletion policy that removes metadata and its sample file together.

The Expo Go sandbox is not the native app sandbox. Existing attempts and calibration cannot magically appear in Swift. Before native device testing, add a one-time Expo export that produces a schema-2 JSON bundle; the native importer converts it to schema 3 and keeps the original file.

## Testing strategy

### Golden parity tests

Export representative captures from Expo:

- labelled Phone Flip and Reverse Phone Flip;
- both shuvit directions;
- Front Flip and Back Flip;
- Straight Air;
- fast/low and slow/high variants;
- deliberate misses and false-positive motions;
- calibration captures.

Run each fixture through TypeScript and Swift. Assert segmentation boundaries within one sample, rotations within tolerance, replay endpoints and expected top candidates. Port the existing 29 unit tests before tuning native thresholds.

### Native tests

- Swift Testing for math, state machines, scoring, persistence migrations and parameterized fixtures;
- XCTest UI tests for onboarding, Play, Result, Recent and replay controls;
- XcodeBuildMCP for build, launch, screenshots, UI tree, logs and regression reproduction;
- physical-device sessions for Core Motion, haptics, thermals, interruptions and real 100 Hz delivery;
- Instruments gates for SwiftUI hitches, energy, allocations and leaks.

### Initial quality gates

- no detector sample dropped because the UI renders;
- replay Play, scrub and camera orbit work in Practice and saved attempts;
- 55+ FPS on the target iPhone during Play with diagnostics disabled;
- measured motion rate and dropped-sample count recorded per attempt;
- backgrounding stops capture and returns to a safe state;
- no attempt is saved without its raw evidence;
- cold launch and schema migration preserve history.

## Migration sequence

### Phase 0 — freeze and export

- Keep `expo-game-v0.3.0` immutable.
- Add schema-2 JSON export to Expo.
- Commit a small reviewed set of anonymized/labelled golden fixtures.
- Write a parity report from the current TypeScript detector.

Exit: every important behavior has data, a test or an explicit product decision.

### Phase 1 — native skeleton

- Create `native/Kamikaze.xcodeproj` with SwiftUI lifecycle, iPhone portrait and iOS 18 target.
- Add app, Swift Testing and XCTest UI targets.
- Add the two local Swift packages and dependency protocols.
- Implement navigation, theme tokens, glass fallback and fixture mode.

Exit: Codex can build, launch and screenshot the shell from the command line and Simulator.

### Phase 2 — motion-core parity

- Port value types, quaternion math, segmentation, manual capture, replay sampling and trick matching.
- Make all golden fixtures pass before changing thresholds.
- Add the Core Motion adapter and live diagnostic surface.

Exit: Swift results match the frozen detector within documented tolerances.

### Phase 3 — the official vertical slice

- Implement onboarding, Play, Result, replay, Again and Recent.
- Use real Liquid Glass on iOS 26 and fallback on earlier versions.
- Persist attempts and raw samples.
- Validate on Simulator with fixtures and on the physical iPhone with real throws.

Exit: this build is at least as understandable and playable as Expo for the core loop.

### Phase 4 — detector improvement

- Collect corrected labels instead of expanding the trick list prematurely.
- Improve low/fast segmentation and Unknown handling.
- Add template matching and detector A/B evaluation against frozen fixtures.

Exit: improvements are measured by precision/recall per trick, not anecdotes alone.

### Phase 5 — product expansion

- Practice progression and target/measured comparison;
- full Profile/history, Locker and progression;
- replay video export with AVFoundation;
- WidgetKit stats/deep-link control and optional Live Activity;
- TestFlight, privacy material and App Store assets.

A widget may display stats and open an armed session, but WidgetKit does not run continuously and cannot own live gyroscope detection.

## Toolchain and Codex workflow

Required locally:

- Xcode 26 selected as the active developer directory;
- one iOS Simulator runtime, not every optional platform runtime;
- Swift 6 strict-concurrency warnings enabled;
- the official Codex `Build iOS Apps` plugin;
- XcodeBuildMCP supplied by that plugin;
- a real iPhone for sensor acceptance tests.

The normal loop is CLI-first:

```text
swift test (MotionCore)
        -> xcodebuild test (app integration)
        -> build and launch Simulator
        -> inspect UI/logs/screenshots through XcodeBuildMCP
        -> install on iPhone for real-motion validation
```

Simulator automation cannot validate gyroscope behavior. Fixture injection is therefore a first-class app capability in Debug builds, not a temporary hack.

## Decisions to make before Phase 1 ends

- Keep iOS 18 compatibility or require iOS 26.
- Confirm the official bundle ID and signing team.
- Decide whether old Expo attempts are valuable enough to import or only become fixtures.
- Confirm right/left hand naming and the physical definitions of shuvits and flips.
- Choose the first target iPhone for performance gates.

These decisions affect compatibility and data, but none block the initial project skeleton or pure motion-core port.
