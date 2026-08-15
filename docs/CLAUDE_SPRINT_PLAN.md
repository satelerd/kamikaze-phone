# Claude native sprint plan — 2026-08-15

Status: working plan for the Claude session sprint on branch `claude/native-sprint`,
based on `origin/ios/capture-segmentation` (`15a3b4a`). It executes existing plans —
`PROFILE_LOCKER_STATS_V1.md` (G1–G5), `PRACTICE_PROGRESSION_V1.md` (P1–P4) and
`NATIVE_EXPERIENCE_SYSTEM_V1.md` (X1–X7) — it does not redefine them.

## Verified starting state

- Branch `claude/native-sprint` created from `origin/ios/capture-segmentation`
  (23 commits ahead of `main`; all of the recent Codex work is pushed there).
- `KamikazeMotionCore`: 35 tests in 10 suites pass on the Mac mini (Swift 6.3.3).
- `xcodebuild` Debug build for iPhone 17 Pro Simulator succeeds; the app installs,
  launches, and renders onboarding, Play (expected `SENSOR ERROR` in Simulator),
  Practice, Locker and Me.
- `KamikazeUITests` pass (3 tests). Note: the shared `Kamikaze` scheme's test action
  does **not** include the `KamikazeTests` unit bundle; run it explicitly with
  `-only-testing:KamikazeTests`.
- iPhone 15 Plus "SAT" (`iPhone15,5`, CoreDevice `CC541726-5B60-5FD5-B914-0D230282A9C3`)
  is paired and `available` from the mini.
- Known packaging issue: `swift test` for `KamikazeMotionApple` fails standalone on
  macOS (platform declaration mismatch with MotionCore). Not a product bug; candidate
  one-line fix in its `Package.swift`.

## Device deploy protocol (as validated by the 2026-08-12 session)

```sh
xcodebuild -project apps/ios/Kamikaze/Kamikaze.xcodeproj -scheme Kamikaze \
  -configuration Debug -destination platform=iOS,id=<device-id> \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-id> <path/to/Kamikaze.app>
xcrun devicectl device process launch --device <device-id> tech.sateler.kamikazephone.dev
```

- Signing: Personal Team (`Apple Development — mini-sat`). Free profiles expire after
  **7 days**; the 2026-08-12 install expires ~2026-08-19. Reinstalling refreshes it.
- Bundle ID `tech.sateler.kamikazephone.dev` stays constant so the on-device history
  (62 captures) survives every reinstall.
- Simulator validates UI only. Every sensor-behavior change needs a physical session
  per `AGENT_EXECUTION_PLAYBOOK.md`.

## Sprint order

Dependency-ordered; each slice ends green (tests + Simulator) and device-checkpointed
when it changes player-facing behavior.

| # | Slice | Source plan | Status | Why here |
|---|---|---|---|---|
| 1 | Attempt summaries + pagination | G1 | **DONE** (`3aaa576`) | Unblocks Profile/Stats/Practice; Profile previously decoded every raw payload per refresh |
| 2 | Honest Practice library + practice run | P1–P2 | **DONE** (`80a5f1a`) | Six detector-ready tricks exist; turns the Practice shell into gameplay |
| 3 | Honest Profile + full History + Motion Tape | G2 | **DONE** (`22b0234`) | Editable identity, filterable history on summaries, one `AttemptDetail`, atomic deletion |
| 4 | Stats engine + Overview/Tricks/Records | G3 | **DONE** (`93872e1`) | Deterministic reductions over summaries |
| 5 | Glass role hierarchy | X2 | pending | `GlassEffectContainer`, roles, morphing IDs, one fallback boundary |
| 6 | Slipstream Field v2 | X3 | pending — requires the X1 `ExperienceState` contract first | One field at the app shell, phase/energy-driven |
| 7 | Phone Studio + Setup prototype | X4/G4 | pending | Shared `PhoneModelFactory`, quality 15 Plus-class asset, live appearance propagation |
| 8 | Feedback engine scaffold | X6 | pending | Coordinator + AHAP cues authored; capture-window cues stay disabled until the physical contamination bench passes |

Practice mastery (P3), reward ledger (G5), choreography (X5) and integration passes
(X7) follow if the sprint reaches them.

## Physical checkpoints Daniel is needed for

1. Device smoke test after slice 2 (first gameplay-affecting build).
2. Device test of History/pagination with the real 62-attempt history (slice 3).
3. Contamination bench before any capture-window haptic/audio cue ships (slice 8):
   stationary phone, 20 repetitions per cue, gyro/accel baseline vs. peak comparison.

## Git protocol

- All work on `claude/native-sprint`; upstream intentionally unset so `git push`
  cannot land on the Codex branch. First push: `git push -u origin claude/native-sprint`.
- One intentional commit per slice, master-plan review checklist applies.
- No merges to `main`; hand back to the Integrator (Codex/Daniel) via PR review.
