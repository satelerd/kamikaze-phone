# Handoff: Claude → Codex (2026-08-16)

Claude worked on branch `claude/feedback-r1` from 2026-08-15 to 2026-08-16: a native
experience sprint plus six player-feedback rounds, each installed to Daniel's physical
iPhone and reviewed by him. This doc is the contract for continuing that work. **Read
the "Divergences from the plan docs" section before touching anything** — several
things deliberately contradict the older plans in `docs/`.

## Branch map (all linear, no merges pending conflicts)

```
main (d4a0eba, detector checkpoint merged via PR #7)
 └─ ios/motion-schema-fixtures   4 commits — PR #8 (DRAFT, superseded, close it)
     └─ ios/capture-segmentation   23 commits total over main — Codex, Aug 9–15
         └─ claude/native-sprint     8 commits — Claude sprint (X1–X4, G1–G4, P1–P2)
             └─ claude/feedback-r1   +9 commits — feedback rounds 1–6.5 (tip c7fa0e1)
```

Totals over main: 40 commits, 101 files, +15,412/−353.
Claude's share (over `ios/capture-segmentation`): 17 commits, 64 files, +6,978/−677.

## PR plan (prepared, NOT executed — Daniel green-lights)

Two stacked PRs so authorship stays legible:

1. **PR-1** `ios/capture-segmentation` → `main` — the Codex evidence/detector work.
   Close draft #8 as superseded when this is created (capture-segmentation contains
   all 4 of its commits).
   ```
   gh pr create --base main --head ios/capture-segmentation \
     --title "iOS: capture segmentation, device-validated detector v0.2, evidence pipeline"
   ```
2. **PR-2** `claude/feedback-r1` → `ios/capture-segmentation` — the Claude sprint +
   rounds. GitHub retargets it to `main` automatically when PR-1 merges and its
   branch is deleted.
   ```
   gh pr create --base ios/capture-segmentation --head claude/feedback-r1 \
     --title "Native experience sprint + player feedback rounds 1–6"
   ```

PR #9 (MAXMARDONES, `apps/web` browser build) is external and out of scope here.

## What Claude built, by system

- **Play/Practice live stage** — `NativeRunModel` publishes pose at ~50 Hz and numeric
  telemetry at 8 Hz over the 100 Hz sensor stream; `LiveRunStage` / `RunTelemetryHUD`
  subviews isolate @Observable invalidation so the host screen only re-evaluates on
  phase changes. Play redesigned: header "KAMIKAZE PHONE FLIP" (no period — player
  call), no status subtitle, THROW/CANCEL primary button, stage zoom 0.33.
- **Sensor-stream backpressure fix** — see the concurrency contract below. Critical.
- **Phone models** — `PhoneModelLibrary` is multi-asset (`PhoneAssetID`: `.scanned`
  REAL 15 PRO by MajdyModels CC BY 4.0; `.paintable` PAINT 15 low-poly by LagzDesign
  CC BY, 2.5k tris). PAINT 15 is tintable: back = BODY color with hue-preserving
  luminance boost (`min(1/0.36, 1/max(r,g,b))`), frame = EDGE color. Normalization
  includes a lateral-yaw fix (extents.z > extents.x → rotate π/2 in Y). PBR assets
  need `SimpleMaterial` replacement or IBL washes them out.
- **Custom photo screen** — `CustomScreenStore` persists one image (App Support,
  EXIF-normalized, ≤1024px). The PAINT 15 GLTF mesh expects a vertically pre-flipped
  texture (its UVs compensate); the procedural box uses the upright one. Both
  variants are cached; `revision` counter drives refresh.
- **Measured vertical arc** — `FreefallWindow` in `ReplayBuilder` (KamikazeMotionCore):
  longest run of accelG ≤ 0.55 sustained ≥ 120 ms → h = g·T²/8, pure ballistics.
  Presentation-only; the detector is untouched. Replay shows MEASURED ARC + AIR/PEAK
  stats. Threshold may truncate on violent spins (>720°/s) — calibrate with real
  throws before trusting PEAK.
- **Honest counters** — `AttemptSummaryV1.countsAsSuccess`: human verdict wins when
  present (landed = success); unreviewed attempts count as success iff the detector
  recognized them; NEEDS REVIEW / UNKNOWN read as misses. Applied everywhere: ME
  stats, streaks, activity days, records, per-trick stats.
- **TRICKS stats tab** — headline is throw count per trick (sorted by it), bar track
  length ∝ attempts vs. most-thrown, volt fill ∝ landed share. Unidentified misses
  intentionally don't appear per-trick (no trick to attribute them to).
- **Setup auto-save** — `AppearanceStore.applyChange` mutates + persists per tap; the
  preview/equip API and EQUIP/DISCARD bar are gone. Don't reintroduce them.
- **Replay** — default speed 0.5× (study speed), spectator camera distance 0.34,
  pinch floor 0.30, arc render cap 0.22 m to stay framed.
- **Experience fields** — FLUX is the default; FACETS and HORIZON exist but Daniel
  dislikes them (kept for the Beta bench, don't promote). Sound pair for
  detection success/failure is approved.

## Divergences from the plan docs (do NOT "fix" these back)

| Doc says | Reality now | Why |
|---|---|---|
| PROFILE_LOCKER_STATS_V1 G3: only human-confirmed attempts count | `countsAsSuccess` counts detector-recognized unreviewed attempts | Daniel's explicit call, 2026-08-16 |
| Setup equips via preview + EQUIP button | Auto-save on every tap | Daniel's explicit call, round 6 |
| Replay plays at 1× | Default 0.5× | Real tricks resolve in ~300 ms; 1× reads as a blink |
| Arc was "estimated from duration" (Beta bench copy) | Arc is measured via `FreefallWindow` | Daniel rejected the estimate as meaningless |
| START SESSION button | THROW (alt copy "SEND IT" offered, verdict pending) | Round 6 redesign |

## Concurrency contract of NativeRunModel (do not simplify)

The 100 Hz sensor stream previously `await`ed the MainActor per sample through an
unbounded AsyncStream buffer. Under UI load the queue grew and poses arrived ever
older — the "Play gets slow, then stops detecting" bug. The fix:

- **Pure pose events** go through a latest-wins mailbox (`OSAllocatedUnfairLock`):
  a new pose overwrites the pending one, a single scheduled MainActor drainer
  consumes it. Poses are *droppable by design*.
- **Phase changes and completed results** bypass the mailbox and are awaited in
  order (`phaseAuthoritative: true`). A drained stale pose must never regress the
  phase — that's what the `phaseAuthoritative: false` path is for.
- `dismissResult()` restarts the stream — closing a result with X used to leave the
  stage dead until re-arm.

Any refactor that makes every event awaited again reintroduces the bug. **Status:
not yet validated on device** (simulator has no Core Motion). If Daniel still sees
degradation: HUD RATE ≈ 100 HZ with a sluggish stage → rendering problem (go to
Instruments); RATE collapsing → stream problem.

## Frozen things

- **Detector v0.2 is frozen and physically validated**: 19/19 landed + 6/6 misses on
  an independent holdout (62 captures). Do not re-tune it against those two
  sessions. New tuning requires new labelled captures.
- Bundle ID stays `tech.sateler.kamikazephone.dev` (keeps install history).

## Build & deploy gotchas

- Work from `apps/ios/Kamikaze/`. The pbxproj carries no team → CLI builds need
  `DEVELOPMENT_TEAM=U6FHW3K5AY -allowProvisioningUpdates`.
- DerivedData has THREE sibling `Kamikaze-*` dirs. Pick products by newest mtime
  (`ls -dt ... | head -1`), never `find | head -1` — that once installed a stale
  binary and produced a false visual regression.
- Deploy: `xcodebuild -destination platform=iOS,id=00008120-0009385014D0A01E ... build`
  then `xcrun devicectl device install app --device CC541726-5B60-5FD5-B914-0D230282A9C3 <app>`.
  Free Personal Team signing = 7-day profile; reinstalling renews it.
- Simulator (iPhone 17, `A20D2B71-74BA-47EC-9B51-83EACFD54161`) validates UI only —
  no Core Motion. `-debugInitialTab play|locker|beta` jumps tabs at launch.

## Tests

- App: `xcodebuild ... -destination "platform=iOS Simulator,id=A20D2B71-…" test`
  (67 unit in `KamikazeTests`, 3 UI in `KamikazeUITests`).
- Package: `swift test` inside `Packages/KamikazeMotionCore` (43 tests, includes
  `FreefallWindowTests`) — **not in the app scheme**, run it separately.
- All green at `c7fa0e1`.

## Open work

1. **Await Daniel's round-6.5 verdict** — especially whether the stream fix killed
   the Play degradation on device, and THROW vs. SEND IT copy.
2. Calibrate the `FreefallWindow` threshold (0.55 g / 120 ms) against real throws.
3. From the sprint plans: P3 target-vs-measured refinements, X5 choreographies,
   X7 integration pass; G5 is blocked on Game Score v1.
4. Physical contamination bench for feedback cues during capture (haptics are
   gated off during the evidence window until proven clean).
