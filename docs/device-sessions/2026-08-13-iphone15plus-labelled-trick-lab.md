# iPhone 15 Plus labelled Trick Lab dataset — 2026-08-13

## Source and integrity

- Transport: WhatsApp/Baileys document received by the local Hermes bridge.
- Export format: `kamikaze.labelled-motion-dataset.v1`.
- Source SHA-256: `6c2c9c41cb3500cf59706bbda88b16d3b4784971039716f3abe5dd9f34a23bf9`.
- Local working copy: `datasets/inbox/2026-08-13-whatsapp/kamikaze-labelled-dataset-v1.json` (ignored by Git).
- Device: `iPhone15,5`, iOS 26.0 build 23A340, portrait, right hand, with case.
- Capture window: 2026-08-13T19:24:28Z through 2026-08-13T20:23:14Z.

The export contains 37 unique captures and 15,066 native schema-v3 samples.
Measured frequency averages 100.29 Hz (100.24–100.31 Hz). All 37 embedded
payload checksums validate using the production Codable schema. Attempt IDs,
sample counts and payload IDs agree; timestamps are strictly increasing;
sequences are contiguous; no quality flags, timestamp gaps or sequence gaps
are present.

Twenty-four captures use `manual-capture-auto-primary-burst-v2`; the 13 older
captures use the broader `manual-ui-markers-v1`. Do not compare durations
between these cohorts without first normalizing their boundaries.

## Human labels

| Trick | Captures | Landed | Missed |
|---|---:|---:|---:|
| Flip | 4 | 3 | 1 |
| Reverse Flip | 4 | 2 | 2 |
| Phone Flip | 11 | 8 | 3 |
| Reverse Phone Flip | 8 | 7 | 1 |
| Backside Shuvit | 5 | 4 | 1 |
| Frontside Shuvit | 5 | 4 | 1 |

Conditions include 15 standard, 8 high/freefall, 7 fast/low and 7 negative
control captures. Human labels and outcomes are ground truth;
`automaticObservation` is diagnostic output from `debug-recorder/v1`, not a
validated confidence probability.

## Initial feature finding

Median integrated gyro features for landed captures:

| Human trick | Net rotation X/Y/Z | Angular path X/Y/Z | Dominant-axis purity |
|---|---|---|---:|
| Flip | −9° / +381° / −27° | 59° / 443° / 50° | 0.81 |
| Reverse Flip | +24° / −362° / +1° | 66° / 394° / 40° | 0.79 |
| Phone Flip | +11° / +484° / −13° | 383° / 591° / 243° | 0.49 |
| Reverse Phone Flip | −22° / −463° / −3° | 354° / 541° / 227° | 0.48 |
| Backside Shuvit | +12° / −13° / +346° | 157° / 161° / 370° | 0.53 |
| Frontside Shuvit | −37° / −14° / −334° | 249° / 241° / 358° | 0.43 |

This is the first strong physical evidence explaining the Flip/Phone Flip
confusion. Both finish with a large signed Y rotation, so a matcher based only
on final integrated rotation collapses them into one class. A landed Flip is a
comparatively pure Y-axis motion. A Phone Flip — the phone equivalent of a 360
Flip — has substantial X/Z angular path even though those signed components
mostly cancel by the end. The recognizer therefore needs path shape, axis
purity and temporal sequencing; a fixed `Y + signed Z` target is not an
accurate representation of the measured trick.

The same dataset also shows that failed controls can receive high legacy rule
fits. Landing quality must remain a separate decision from trick identity, and
low fit must be presented as review/unknown rather than forced into a trick.

## Next evidence gate

1. Split the 24 guided primary-burst captures into development and untouched
   holdout groups before changing recognition rules.
2. Promote reviewed captures as individual v3 fixtures with provenance and
   hashes; keep the monolithic raw export outside Git.
3. Add path-distribution and temporal-axis features to MotionCore.
4. Evaluate identity and landed/missed decisions separately, reporting a
   confusion matrix and abstention rate.
5. Validate the tuned policy with a second physical session rather than tuning
   repeatedly against this one hour of data.

## Follow-up result

The split, evaluator and v0.2 angular-path matcher were implemented after this
report's initial analysis. See
`datasets/evaluations/iphone15plus-right-2026-08-13-matcher-v02.md` for the
frozen before/after result. Further threshold changes require a new physical
session; this first holdout must not become an iterative tuning set.
