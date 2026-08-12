# Kamikaze: Phone Flip — native beta execution plan

Status: approved for implementation on 2026-08-12. Native application work starts on branch `codex/native-beta`.

This document turns the migration architecture into an executable workflow. Work begins only after Daniel approves the product decisions and the first implementation phase.

The complete product-development roadmap and reusable subagent briefs now live in [`DEVELOPMENT_MASTER_PLAN.md`](./DEVELOPMENT_MASTER_PLAN.md) and [`AGENT_EXECUTION_PLAYBOOK.md`](./AGENT_EXECUTION_PLAYBOOK.md).

## Product stages

- **Prototype:** the original sensor laboratory and interaction experiments.
- **Alpha:** the frozen Expo game at tag `expo-game-v0.3.0`; playable reference, dataset source and behavioral specification.
- **Beta:** a native SwiftUI app that preserves the alpha's proven loop while rebuilding its foundations for reliability, native interaction and future expansion.

The beta is not a line-by-line conversion. It should reproduce the product behavior and the recorded motion evidence while improving ownership, tests, persistence, concurrency and rendering boundaries.

## Approval gate

Before creating `apps/ios/`, confirm:

1. minimum iOS version;
2. bundle identifier and signing team;
3. what Expo data must be imported;
4. first beta feature boundary;
5. target iPhone, default grip hand and trick-direction vocabulary;
6. which available Codex models may substitute for Luna until Luna is exposed to subagent spawning.

After those answers, start with Phase 0 only. Do not silently expand the beta into Practice progression, accounts, social features, widgets or the Locker economy.

## Approved decision record — 2026-08-12

- **Platform:** prioritize the iOS 26 experience and native Liquid Glass. Keep an intentional compatibility fallback for earlier supported versions; start with iOS 18 as the deployment target and revisit it before TestFlight.
- **Signing:** use Daniel's Apple account and Personal Team during local development. Paid-team/TestFlight distribution remains a later release decision.
- **Expo data:** import a curated, labelled set of real attempts and calibration captures as golden fixtures. Do not make full-history migration a Phase 0 dependency.
- **Beta scope:** retain everything already present in the alpha—Onboarding, Play, Result/Replay/Recent, Practice, Locker, Profile, Workshop/calibration and settings—but implement it in vertical slices. Core Play reliability remains the first quality gate; the other areas stay in scope rather than being permanently deferred.
- **Reference hardware:** iPhone 15 Plus, right-handed grip. Runtime code must not assume that model's dimensions, refresh rate or sensor delivery. Support modern iPhones that meet the chosen iOS target, record actual sample timing and degrade diagnostics honestly when sensor delivery differs.
- **Agents:** current Sol session is the integrator. Terra subagents may handle bounded audits and implementation tasks. No Luna claim or silent substitution while Luna is unavailable to this session's subagent tool.

This record authorizes Phase 0 and the initial native skeleton. It does not authorize App Store submission, paid enrollment, destructive migration of Expo data or global Codex configuration changes.

## Implementation checkpoint — 2026-08-12

- Xcode 26.6, Swift 6.3.3 and the iOS 26.5 Simulator runtime are installed and working.
- The versioned project lives at `apps/ios/Kamikaze/Kamikaze.xcodeproj`; its shared scheme builds and runs from the command line.
- The app currently provides the native SwiftUI shell for Onboarding, Play, Practice, Locker, Profile and Workshop. It is a structural preview, not working native sensor gameplay yet.
- `KamikazeMotionCore` is a pure local Swift package. Its first replay/quaternion contracts pass against two labelled iPhone 15 Plus, right-hand Phone Flip fixtures.
- Expo now has an explicit local-data export action. The next evidence gate is exporting Daniel's current attempts and calibrations, then curating the additional shuvit/front/back fixtures.
- Personal Team signing remains intentionally absent from version control. It is configured only in the ignored local signing file, and the development build has been installed on Daniel's iPhone.

## Device-motion checkpoint — 2026-08-12

- `KamikazeMotionApple` now owns the Core Motion boundary and emits sendable, unit-explicit frames without leaking `CMDeviceMotion` across concurrency domains.
- Play requests 100 Hz device motion, reports the measured rate and gyroscope magnitude, establishes an initial screen-facing baseline and supports an explicit Zero Pose.
- The live phone is now a RealityKit scene with orbit, pinch and camera reset. Simulator correctly reports motion unavailable; physical-device coordinate/sign validation is the next acceptance gate.
- An experimental automatic detector now exists and has been physically smoke-tested. It is still a transitional combined segmenter/classifier; recorded replay and persistence remain absent.

## Visual-system checkpoint — 2026-08-12

- Player feedback asks for Liquid Glass to read as a defining material rather than an occasional effect: primary actions, cards, selectable tiles and the phone stage should all use the shared native glass boundary.
- The background direction is a slow, abstract kinetic light field that gives the glass something meaningful to refract. The native implementation uses animated SwiftUI `MeshGradient` and `Canvas`, not WebGL, and respects Reduce Motion and Reduce Transparency.
- The visual identity remains pitch black, Ion blue, Hazard coral, Volt acid and Frost white. Motion is concentrated in the background and play-state transitions so the interface does not become noisy.
- Visual polish does not move the core gate: physical-device validation, truthful capture, segmentation, trick detection, replay and persistence remain ahead of Practice/Locker/Profile feature completeness.

## Physical Play checkpoint — 2026-08-12

- The app is signed with Daniel's Personal Team, installed on the reference iPhone 15 Plus and trusted locally.
- Core Motion and the live RealityKit phone pose were validated physically; the visualizer follows the device correctly.
- Detector commit `179e124` adds an initial automatic detector with freefall and gyro-burst triggers, pre-roll, settling and a bounded timeout. Daniel confirmed the updated flow closes real attempts more reliably.
- Synthetic native tests cover a low Phone Flip, a low shuvit and the no-hang timeout. This is behavioral evidence, not a physical-accuracy claim.
- The detector and visual foundation were separated into commits `179e124` and `e0862b6`. Section 0 records their tests, physical smoke test, known issues and annotated checkpoint tag.
- Native persistence, Result/Recent, recorded replay, calibration and complete Practice/Locker/Profile behavior remain the next product spine.
- Daniel completed the checkpoint smoke test across normal, malformed, fast and high attempts. Front/Back rotations were plausible, malformed attempts generally fell below 70% confidence and a Frontside Shuvit exposed the missing directional label. The qualitative session is recorded under `docs/device-sessions/`; raw attempts were unavailable because persistence does not exist yet.

## Agent strategy

The primary agent is the integrator. It owns architecture decisions, shared contracts, sequencing, review and the final branch. Subagents receive small, bounded tasks with explicit files and acceptance criteria.

Parallel work is appropriate for read-only audits, fixture analysis and independent test design. Write-heavy work stays sequential whenever two tasks could touch the Xcode project, shared models, dependency container or design system. The goal is trustworthy integration, not maximum agent count.

### Model availability

Desired model: `gpt-5.6-luna`.

Luna is an official model family, but this active Codex collaboration environment currently exposes only these explicit subagent overrides:

- `gpt-5.6-sol`;
- `gpt-5.6-terra`.

Therefore the current session cannot honestly promise a Luna subagent. Recommended temporary mapping, subject to Daniel's approval:

- primary/integrator: current Sol session;
- bounded implementation, test and audit subagents: Terra;
- high-risk architecture or motion-math changes: Sol or primary-agent review.

If local Codex later exposes Luna through custom agent configuration, use Luna for fixture analysis, documentation, deterministic test generation and other well-bounded high-volume work. Do not change global Codex configuration or substitute a model without approval.

## Proposed roles

These are roles, not four permanently running agents. Spawn only the role needed for the current phase.

### 1. Motion parity

Owns the cross-language data contract, exported fixtures, quaternion math, segmentation and classifier parity. Initially read-heavy; later writes only inside `apps/ios/Packages/KamikazeMotionCore`, its tests and approved fixture tooling.

### 2. Native shell

Owns the SwiftUI lifecycle, navigation, design tokens, accessibility, dependency injection and persistence shell. It does not tune the detector or invent 3D behavior.

### 3. Replay and 3D

Owns the reusable RealityKit phone scene, timestamped replay, play/pause, scrubbing, speed, orbit, pinch, Reset Camera and Zero Pose. It consumes motion contracts and cannot redefine them.

### 4. QA and release

Owns build/test automation, fixture-mode UI tests, performance checks, device test scripts and TestFlight readiness. It may diagnose failures but sends implementation fixes back to the owning role.

## Sequencing

### Gate A — preserve the alpha

- verify tag `expo-game-v0.3.0` and the current remote branch;
- export representative attempts and calibration sessions from Expo;
- label the captures and record known alpha behavior;
- produce a parity report before tuning anything.

Exit: every core trick and known replay edge case has evidence.

### Gate B — create the native skeleton

- create the iOS project and local Swift packages;
- establish CI-friendly schemes and fixture mode;
- build and launch a minimal shell in Simulator;
- add the design-system glass/fallback boundary.

Exit: command-line build, tests and screenshots are deterministic.

### Gate C — motion parity

- port immutable value types and math first;
- port segmentation and replay sampling;
- run golden fixtures in TypeScript and Swift;
- document every intentional difference.

Exit: the native engine matches the alpha within declared tolerances.

### Gate D — playable vertical slice

- onboarding and motion permission;
- Play state machine and live phone;
- capture, result, replay, save, Recent and Again;
- real-device validation with corrected player labels.

Exit: one-trick play is at least as understandable and reliable as the alpha.

### Gate E — beta expansion

Only after the vertical slice passes: complete the in-scope Practice progression, richer Profile/history, Locker and Workshop parity. Sharing/video export, lines, widgets, accounts and social features remain later expansion work.

## Prompts for future subagents

Each prompt must be amended with the exact branch, current phase and decisions already approved.

### Motion parity prompt

```text
You own a bounded motion-parity task for Kamikaze: Phone Flip.

Read docs/NATIVE_SWIFT_MIGRATION.md, docs/NATIVE_BETA_EXECUTION.md and the relevant files under apps/expo/src/motion. Treat tag expo-game-v0.3.0 as the behavioral baseline. Do not modify UI, Xcode project settings, signing, persistence or unrelated Expo code.

Task: [one exact contract, fixture export, algorithm or test group].
Allowed paths: [explicit paths].
Required evidence: existing TypeScript tests, named fixture files and mathematical invariants.
Acceptance: deterministic tests pass; units and coordinate frames are documented; intentional parity differences are reported.

Do not commit, push or broaden scope. Return changed files, tests run, results, risks and one recommended next task.
```

### Native shell prompt

```text
You own one bounded SwiftUI-shell task for the Kamikaze native beta.

Read both native planning documents and the approved decision record. Preserve the Expo alpha as a reference; do not translate React components line by line. Do not change motion algorithms or RealityKit replay contracts.

Task: [one navigation, design-system, persistence or lifecycle slice].
Allowed paths: [explicit paths].
Acceptance: xcodebuild succeeds, relevant Swift tests/UI tests pass, iOS 26 Liquid Glass and the approved older-iOS fallback remain behind one abstraction, and accessibility/reduced-motion behavior is covered.

Do not commit, push or add dependencies without approval. Return changed files, commands, screenshots/log evidence, risks and next task.
```

### Replay and 3D prompt

```text
You own one bounded RealityKit/replay task for the Kamikaze native beta.

Consume the established MotionSample and ReplayFrame contracts; do not redefine detector output. Use one reusable PhoneSceneView for live, replay, target, comparison and locker modes.

Task: [one rendering or interaction capability].
Allowed paths: [explicit paths].
Acceptance: fixture playback visibly changes at the requested timestamp; Play advances continuously; scrub, speed, orbit and pinch work; the 3D gesture does not scroll its parent; Reset Camera and Zero Pose remain distinct; offscreen work pauses.

Do not commit or push. Return changed files, build/tests, simulator evidence, performance observations and remaining risks.
```

### QA and release prompt

```text
Audit one bounded native-beta quality gate. Prefer read-only diagnosis and tests. Do not redesign product behavior.

Scope: [build, replay regression, fixture parity, performance, device session or signing readiness].
Required tools/evidence: [xcodebuild/XcodeBuildMCP/Instruments/device logs].
Acceptance: reproduce the issue or pass the gate with exact commands, environment, artifacts and observed results.

Do not commit or push. If a fix is required, identify the owning role, likely files and a minimal reproduction instead of editing across ownership boundaries.
```

## Integration protocol

For every implementation task:

1. primary agent records the exact scope and allowed paths;
2. subagent returns evidence without committing;
3. primary agent reviews the diff and shared contracts;
4. primary agent runs the relevant unit and integration tests;
5. physical motion changes are not accepted from Simulator evidence alone;
6. one intentional commit is created only after the slice passes;
7. the migration document and decision record are updated when behavior changes.

If two subagents would edit the same project file or shared model, run them sequentially. Never let an agent tune thresholds using only synthetic tricks or visual intuition.

## First approved work package

Once Daniel approves starting, the recommended first package is deliberately small:

1. export schema-2 alpha attempts and calibration captures;
2. curate a compact golden-fixture set;
3. generate the TypeScript parity report;
4. create an empty, buildable native project and pure Swift package;
5. port only the sample/quaternion/replay value contracts and tests.

This establishes the evidence and build spine before product UI or detector tuning begins.
