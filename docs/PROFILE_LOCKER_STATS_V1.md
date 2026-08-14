# Profile, statistics and Locker v1

Status: product and implementation plan for the native beta. This refines
Section 7 of `DEVELOPMENT_MASTER_PLAN.md`; it does not claim the current shell
already implements these contracts.

## Product jobs

- **Profile / Me:** answer “what kind of player am I becoming?”
- **Stats:** answer “what have I actually landed, and how am I improving?”
- **History:** let the player find, replay, correct, export or delete any attempt.
- **Locker:** turn progress into a visible phone identity applied everywhere.

The source material is a phone used like a board: grip, motion tape, deck
graphics, scuffs and kinetic light. The screens should not look like a generic
fitness dashboard or a conventional ecommerce grid.

## Product boundaries

Keep these systems separate:

1. **Practice progression** is derived from qualifying attempts and mastery.
2. **Statistics** are deterministic views over saved attempts and their current
   versioned interpretation.
3. **Rewards** are explicit, idempotent events. A future matcher re-analysis
   must not silently add or remove already-awarded currency.
4. **Appearance** is a persisted player choice, immediately reflected by every
   live, replay, target and Locker phone scene.

No account, cloud sync, payment or public profile is required for v1. Every
local screen must remain useful offline and be ready to migrate to an account
later without changing attempt IDs.

## Evidence semantics

Player-facing numbers need one documented meaning:

| Metric | v1 definition |
|---|---|
| Attempts | Closed, valid captures; excludes `noAttempt` and corrupt evidence |
| Recognized | Detector-recognized identity, or a valid human trick correction |
| Landed | Human-confirmed landed until Landing Score v1 is physically validated |
| Streak | Consecutive landed attempts in chronological order; a miss breaks it, unclear waits for review, `noAttempt` is ignored |
| High score | Hidden until versioned Game Score v1 exists; FIT must not masquerade as score |
| Best FIT | Identity similarity for one named trick, labelled as FIT rather than quality |
| Fastest / longest | Motion duration among landed attempts of the same trick, never whole capture duration |
| Activity day | Number of landed tricks that local calendar day; timezone stored with the attempt summary |
| Trick count | Landed count grouped by canonical trick ID; legacy IDs are canonicalized first |

An automatic result with no verified execution may appear under Attempts and
Recognized, but cannot inflate Landed, streaks, mastery, records or rewards.

## Information architecture

### Profile home

The page should read as a player identity, not a wall of cards:

```text
┌──────────────────────────────────────┐
│ SAT                         SETTINGS │
│ PHONE FLIP RIDER                     │
│                                      │
│  [ kinetic phone + equipped skin ]   │
│                                      │
│ CURRENT STREAK  4     LANDED  128    │
│                                      │
│ MOTION TAPE ━━━●━━━━●━━○━━━━●━━━━    │
│ latest attempt rows continue below   │
│                                      │
│ [ ALL HISTORY ]       [ ALL STATS ]  │
└──────────────────────────────────────┘
```

Content order:

1. editable local name, joined date and equipped phone;
2. current meaningful accomplishment: current streak or latest mastery;
3. compact landed/activity preview;
4. six recent attempts with status, trick, FIT/score and duration;
5. direct routes to full History, Stats, Settings and Sensor Workshop.

Recent uses the exact same `AttemptDetail` and replay component as the immediate
Result screen. It never builds a second miniature replay engine.

### Statistics

Statistics are progressive disclosure, not twenty numbers on Profile:

```text
OVERVIEW  |  TRICKS  |  RECORDS

OVERVIEW: landed, current/best streak, active days, activity field
TRICKS:   each canonical trick → landed/attempted, best FIT/score, consistency
RECORDS:  fastest, longest, highest, newest mastery; tap to open its replay
```

- The activity field uses four intensities based on landed tricks per day and
  exposes the exact count on tap/accessibility focus.
- A trick detail compares recent attempts only against the same canonical trick.
- Each record links to the immutable attempt that produced it.
- Empty and low-data states explain what to do next; they do not display zeroes
  that look like failure.

### Full History

- filter by trick, landed/missed/unclear, detector/human and date;
- sort newest, oldest, best FIT/score, fastest or longest;
- batch selection is not needed in v1;
- attempt detail supports replay, correction, evidence export and deletion;
- deletion requires confirmation, removes raw and interpretation atomically,
  and deterministically refreshes progression/statistics;
- “Export my data” creates one manifest plus referenced raw payloads.

### Locker

The hero is one interactive RealityKit phone, using the shared scene in Locker
mode. Orbit, pinch and Reset Camera behave exactly like Replay. Selection is
applied live; no tab switch is required.

```text
┌──────────────────────────────────────┐
│ LOCKER                    420 CREDITS│
│                                      │
│       interactive equipped phone     │
│        [ BODY ] [ EDGE ] [ TRAIL ]   │
│                                      │
│  horizontal rail of collectible parts│
│  ION     HAZARD     VOLT     ...     │
│ [ EQUIP ] / [ UNLOCK 180 ]           │
└──────────────────────────────────────┘
```

Start with a deliberately small appearance grammar:

- **Body:** primary material/color;
- **Edge:** frame accent;
- **Trail:** restrained motion/replay trail, disabled by Reduce Motion;
- **Mark:** one optional deck-like graphic or earned badge.

Do not start with arbitrary RGB controls: authored combinations make rewards
recognizable and keep the phone legible in every background state.

## Reward contract

The current prototype's `0 POINTS AVAILABLE` and locked prices are placeholders.
They must not become a fake economy based on detector FIT.

After Game Score v1 is stable, introduce a local `RewardLedger`:

```swift
RewardEvent {
    id
    kind              // earn, spend, grant, refund
    amount
    sourceID          // attempt, mastery, onboarding or purchase ID
    scoreVersion
    createdAt
}
```

- one earn event per source ID makes rewards idempotent;
- re-analysis can update stats but never rewrite historic rewards silently;
- introductory cosmetics may unlock through Practice mastery rather than cost;
- spending creates a transaction; selecting an owned cosmetic costs nothing;
- no real-money purchase language or controls in the native beta.

## Visual direction

Reuse the native motion-instrument system:

| Token | Value | Role |
|---|---|---|
| Pitch | `#090B0A` | field depth |
| Ink | `#141817` | quiet glass backing |
| Frost | `#E9ECF8` | player identity/type |
| Ion | `#5B73FF` | equipped/interactive |
| Hazard | `#FF603F` | miss/review needed |
| Volt | `#D7FF4A` | landed/mastered/reward |

- Display: SF Pro Rounded Black, limited to identity, records and unlock moments.
- Body: SF Pro Text.
- Evidence/data: SF Mono.
- Glass is strongest on thumb actions and selected cosmetics, quieter on passive
  statistic surfaces. The animated field behind it provides refraction depth.
- Signature element: **Motion Tape**, a thin chronological strip whose marks
  encode landed, missed and review states and open the corresponding replay.
  This is the one deliberate aesthetic risk; it comes directly from recorded
  motion and replaces a generic dashboard chart.
- Respect Reduce Motion, Reduce Transparency, Dynamic Type and VoiceOver. No
  statistic or ownership state is communicated only by color.

## Data and architecture

The current `ProfileModel` loads every full raw capture to render a list. That
will not scale. Add a lightweight, versioned summary index:

```swift
AttemptSummary {
    attemptID
    capturedAt
    localDayAndTimezone
    canonicalTrickID
    recognitionStatus
    humanOutcome
    motionDurationMs
    fit
    gameScore
    analysisVersion
    scoreVersion
}
```

Recommended boundaries:

- `AttemptSummaryRepository`: paginated/filterable metadata without raw samples;
- `PlayerStatsEngine`: pure deterministic reduction over summaries;
- `PlayerProfileStore`: local identity/preferences;
- `RewardLedger`: append-only local reward events;
- `AppearanceStore`: owned/equipped components, injected through the app shell;
- `CosmeticCatalog`: versioned authored definitions, not UI tuples;
- `AttemptRepository`: continues owning immutable raw evidence;
- raw samples load only when opening Replay, exporting or re-analyzing.

Persist canonical IDs and catalog versions, not display strings or `Color`.
Use one app-level dependency container so Play, Practice, Profile and Locker see
the same appearance and repository updates immediately.

## Delivery slices

### G1 — definitions and scalable summaries

- freeze the metric table above and add unit tests for every edge case;
- persist capture date/timezone and build/rebuild `AttemptSummary` index;
- canonicalize legacy Shuvit identifiers;
- paginate history without decoding raw samples;
- define deletion transaction and data export manifest.

### G2 — honest Profile and History

- replace hardcoded `SAT` with editable local profile;
- build Profile hierarchy, recent preview and full filtered History;
- route Result and History through one `AttemptDetail`;
- implement correction, export and deletion refresh;
- keep Workshop and diagnostics nested under Settings/Me.

### G3 — Statistics and progression surfaces

- implement `PlayerStatsEngine` and deterministic tests;
- add Overview, Tricks and Records views;
- link every record to its attempt replay;
- add landed activity field and Practice mastery summary;
- hide score-based records until Score v1 is available.

### G4 — Locker and appearance propagation

- replace the static rounded rectangle with shared interactive phone scene;
- define catalog and base owned items;
- add Body/Edge/Trail/Mark selection and live preview;
- inject `AppearanceStore` into every phone scene;
- initially unlock through mastery/grants; add credits only after score/reward gate.

### G5 — reward economy and polish

- add idempotent local reward ledger after Game Score v1;
- unlock/equip feedback, haptics and restrained transitions;
- glass/background/accessibility/performance pass;
- migration tests for existing `selectedSkin` and attempt history;
- device acceptance on large and compact recent iPhones.

## Acceptance gates

- every displayed number has a tested definition and no hardcoded player data;
- 1,000 summaries scroll/filter without loading raw motion payloads or stalling UI;
- deleting/correcting an attempt updates Stats and Practice deterministically;
- a detector re-analysis never rewrites earned/spent reward history;
- skin changes appear immediately in Play, Result, Practice, History and Locker;
- every Recent/record item opens the same working replay detail;
- offline cold launch preserves profile, history, progression, rewards and skin;
- glass remains legible with Reduce Transparency and animation stays smooth with
  Reduce Motion;
- no account or paid transaction is implied by local beta copy.

## Deferred, but designed for

- account identity and cross-device sync;
- social profile, shared replay posts and privacy controls;
- seasonal/remote cosmetic catalog;
- leaderboards, challenges and moderation;
- real purchases and entitlement restoration.

Those systems may sync these local contracts later; they must not replace raw
evidence ownership or make ordinary offline play depend on a server.
