# Native player-feedback datasets

These exports contain immutable raw `MotionCaptureV3` evidence, the machine
observation made at capture time and Daniel's later human review. Human review
is ground truth; machine output is never relabelled as truth.

Datasets in this directory are **development** evidence unless an index entry
explicitly says `holdout`. A capture used to derive a catalog reference,
threshold or score weight may not later be counted as independent validation.

`player-feedback-2026-08-16.json` is the first native play-session dataset:

- 36 reviewed automatic attempts / 6,574 raw samples;
- iPhone, portrait, right-hand grip;
- captures recorded 2026-08-14 through 2026-08-16;
- 34 landed and 2 missed labels;
- includes two highly consistent Double Phone Flip captures;
- contains no axis-calibration choreography and is not an execution/landing
  holdout because it has only two misses.

See `docs/DATASET_AUDIT_PLAYER_FEEDBACK_2026-08-16.md` for the frozen audit and
the exact collection gaps.
