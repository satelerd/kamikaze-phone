# Practice and progression v1

Status: product and implementation plan. Trick Lab selection and canonical
trick identifiers may ship before the full Practice coordinator.

## Product job

Practice teaches one physical motion at a time and gives immediate measured
feedback. It is not another detector lab. The player should understand the
target, try it safely, see target versus actual, and know what to improve.

The loop is:

```text
CHOOSE → WATCH → ZERO → TRY → COMPARE → REPEAT → MASTER
```

## Two separate systems

- **Trick Lab** collects labelled evidence. The player freely chooses a trick,
  records repetitions, reviews the measured replay and labels the outcome.
- **Practice** consumes only detector-ready definitions. It teaches and scores;
  it never silently turns unvalidated synthetic targets into recognition.

Each trick has one readiness state:

1. `collectingEvidence`: selectable in Trick Lab, not scoreable in Practice.
2. `candidateReady`: enough labelled examples to propose a mathematical target.
3. `validationRequired`: matcher candidate exists but holdout is still frozen.
4. `detectorReady`: independent validation passed; Practice can judge attempts.
5. `mastered`: player progression, derived from saved attempts.

## Trick tree

```text
FOUNDATION
  BS Shuvit 180 ──→ BS 360 Shuvit ──┐
  FS Shuvit 180 ──→ FS 360 Shuvit ──┤
                                     ├─→ Phone Flip ──→ Double Phone Flip
  Flip ───────────→ Double Flip ─────┤
  Reverse Flip ───→ Double Reverse ──┤
                                     └─→ Reverse Phone ─→ Double Reverse Phone
```

The exact dependencies remain editable. The first beta should not hard-lock the
whole library: a player may preview every trick, while scored attempts unlock in
the tree once their prerequisite and detector readiness are satisfied.

## Level screen

```text
┌─────────────────────────────────────┐
│ BS SHUVIT                 02 / BASE │
│                                     │
│        interactive target phone     │
│      play · scrub · orbit · 0.5×    │
│                                     │
│  180° horizontal · backside         │
│  Keep the flip axis quiet.           │
│                                     │
│ [ ZERO + START PRACTICE ]            │
│                                     │
│ Attempts  ● ● ○   Best 84            │
└─────────────────────────────────────┘
```

After the catch, the same reusable replay scene shows:

- target and measured phone, individually or overlaid;
- identity match, direction and rotation completion;
- duration and catch stability in plain language;
- one primary cue, such as “22° short” or “too much flip-axis motion”;
- Retry as the dominant thumb action;
- `Not quite?` for a human correction.

## Mastery rule

The first implementation derives progression from `AttemptRepository`; it does
not maintain a second completion flag.

- a rep counts when the target identity is recognized and execution is landed,
  or when a human correction confirms both;
- three qualifying reps unlock the next node;
- mastery requires three qualifying reps in the latest five attempts, with no
  evidence-quality error;
- FIT is identity similarity, never presented as landing probability;
- scores and thresholds remain versioned and can be recomputed from raw evidence.

## Delivery slices

### P1 — honest library

- replace static six-level strings with typed trick nodes;
- show detector readiness and prerequisites;
- allow preview of every target;
- route unsupported tricks to Trick Lab instead of starting a fake scored run.

### P2 — one reusable practice run

- add `PracticeRunCoordinator(expectedTrickID:)` around the existing capture
  engine rather than copying `NativeRunModel`;
- automatic capture with manual fallback;
- persist the same `MotionCaptureV3` and analysis used by Play;
- use the shared `ReplayController` for target and measured playback.

### P3 — comparison and mastery

- target/measured overlay and axis-specific coaching;
- repository-derived reps, unlocks and mastery;
- player corrections feed the same feedback export as Play.

### P4 — polish

- ghost-phone follow mode at 0.25×/0.5×/1×;
- haptic countdown, success vocabulary and reduced-motion equivalent;
- personal best, consistency and compact session summary.

## Future: Lines

A double trick and a line are not the same capture contract. A double trick is
one airborne motion with a larger angular path. A line is an ordered session of
independently segmented attempts:

```swift
LineSession {
    id
    startedAt
    attemptIDs[]
    gapsBetweenAttemptsMs[]
    completionState
    scoreVersion
}
```

The first Lines phase should keep each trick's immutable raw capture, then add
continuity, variety and flow scoring above them. It must not concatenate samples
and ask the single-trick matcher to invent a compound label.

## Acceptance gates

- selecting a Trick Lab class never changes detector thresholds;
- legacy v1 Shuvit labels still decode as the measured 360° variants;
- unsupported classes clearly say `NEEDS DATA`;
- Practice, Result and Recent use the same replay implementation;
- dragging the 3D stage never scrolls the parent view;
- progression survives relaunch because it is derived from saved evidence;
- Lines remain out of the single-trick matcher.
