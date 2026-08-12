# Device session — native detector baseline

- Date: 2026-08-12
- Device: iPhone 15 Plus
- OS: iOS 26.5
- Grip: right hand
- Build branch: `ios/beta-checkpoint`
- Detector commit: `179e124`

## Purpose

Physical smoke test for the first native automatic-capture checkpoint. This session validates player-visible behavior only. The app did not yet persist raw samples, so the individual attempts cannot be replayed or used as golden fixtures.

## Observations reported by Daniel

- Multiple normal Front Flips completed and were labelled correctly.
- Multiple reverse-direction front rotations completed and were labelled correctly as the opposite flip direction (`Back Flip` in the current catalog).
- A Frontside Shuvit was detected as a shuvit, but the player-facing label did not distinguish Frontside from Backside.
- Deliberately malformed or failed front-rotation attempts generally produced confidence below 70%.
- The final two attempts intentionally covered the speed/height range: one very fast Front Flip and one Front Flip thrown as high as practical. Both are qualitative observations only because raw capture persistence was absent.
- Automatic attempts completed instead of remaining armed indefinitely.
- The build was usable enough to continue into evidence capture and persistence work.

## Product hypotheses created by this session

- A provisional missed/unknown presentation boundary around 75–80% may feel intuitive to the player.
- Do not ship that boundary as a calibrated rule yet. Current confidence is a rule-fit value with forced minimums, not a probability.
- Directional shuvit naming must incorporate validated grip/coordinate semantics and physical labelled fixtures.
- The next physical test build must save/export every attempt before requesting more valuable speed, height or failure variants.

## Acceptance outcome

`PASS` for the experimental device-detector checkpoint:

- real sensors and live pose work;
- low and high physical attempts close;
- multiple flip directions receive plausible labels;
- malformed motion receives visibly lower confidence;
- known label/scoring limitations are documented rather than treated as production accuracy.

This pass authorizes the annotated checkpoint tag. It does not authorize persistence, scoring or classifier-accuracy claims.
