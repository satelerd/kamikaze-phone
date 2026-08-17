# Player feedback v1

Kamikaze treats three product concepts as separate values:

1. **Identity** — the trick proposed by the detector and its rules fit.
2. **Execution** — landed, missed, unclear or no attempt. This is human-labelled
   until a separate execution model is validated.
3. **Score** — deterministic motion quality from Game Score v1: completion,
   purity, post-catch stability and flow. Automatic scores remain provisional;
   a human `missed` verdict overrides awarded score to zero.

`FIT` is identity similarity, not confidence, landing probability or game
score. A recognized identity must not be presented as proof of a landing.

Game Score v1 is `game-score-v1-motion-quality-v1`. It deliberately excludes
duration so a fast/low or high throw is not penalized merely for having a
different style. It is shown only for recognized identities or human-confirmed
labels with scoreable evidence. It is not yet a trained landing classifier.

The Result and saved Recent views expose `NOT QUITE?`. A correction stores a
`HumanAttemptReview` beside the versioned machine analysis. Raw motion evidence
remains immutable, and future matcher refreshes preserve the human review.

Profile exposes `EXPORT PLAYER FEEDBACK` after the first reviewed attempt. The
`kamikaze.player-feedback.v1` JSON contains the complete `MotionCaptureV3`, the
machine observation and the human review. Dataset consumers must use the human
review as ground truth and must never infer it from the machine result.

Legacy `front-flip` and `back-flip` identifiers remain decode-compatible but
new data is encoded as `flip` and `reverse-flip`.
