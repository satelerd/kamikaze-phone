# Dataset audit — labelled Trick Lab v4 — 2026-08-16

Source working copy:
`datasets/inbox/2026-08-16-whatsapp/kamikaze-labelled-dataset-v4.json`

SHA-256:
`0d673b027912e693b807f66c8820f6b54e8aad421e432a3caff2bcf22121cb12`

The source export remains ignored because it contains 39 MB of full-resolution
motion evidence. Its versioned development split is
`datasets/splits/iphone15plus-right-2026-08-16-v4-development.json`.

## Integrity

- 118 unique `MotionCaptureV3` records;
- every payload attempt ID, schema version, sample count and embedded SHA-256
  passed `kamikaze-motion-eval` validation;
- zero captures report timestamp or sequence gaps;
- all captures report iPhone15,5, iOS 26.0, portrait orientation, right-hand
  grip and approximately 100 Hz sampling;
- 90 human-labelled landed executions and 28 human-labelled misses;
- `automaticObservation` remains diagnostic only. Human labels are truth.

## Coverage

| Human label | Landed | Missed | Total |
|---|---:|---:|---:|
| Phone Flip | 19 | 4 | 23 |
| Reverse Phone Flip | 10 | 2 | 12 |
| Flip | 7 | 2 | 9 |
| Reverse Flip | 5 | 3 | 8 |
| Backside 360 Shuvit | 7 | 2 | 9 |
| Frontside 360 Shuvit | 7 | 2 | 9 |
| Backside Shuvit 180 | 13 | 3 | 16 |
| Frontside Shuvit 180 | 12 | 6 | 18 |
| Double Flip | 5 | 4 | 9 |
| Straight Air | 5 | 0 | 5 |
| **Total** | **90** | **28** | **118** |

The export spans 41 standard, 24 fast/low, 27 high/free-fall and 26 negative
control captures. Case state is nuisance metadata, not a trick label: 37 older
captures say `withCase` and 81 say `unknown`. That does not block identity work.

## Frozen detector v0.2 result

The detector was evaluated without tuning it against v4:

- known-class landed identity: **54 / 55 (98.2%)**;
- missed attempts correctly abstained: **28 / 28 (100%)**;
- overall landed identity including not-yet-modelled classes: **54 / 90**.

The sole known-class landed miss was a Phone Flip placed in review rather than
recognized. The apparent overall drop is expected and useful: v0.2 has no
definitions for 180 Shuvits or Double Flip, and Straight Air currently stays
below its recognition gate. Specifically, landed evidence currently resolves
as follows:

- 180 Shuvits are proposed as their same-direction 360 Shuvit;
- Double Flip is proposed as Phone Flip;
- Straight Air usually abstains and occasionally proposes a low-fit rotating
  class.

This is evidence of missing classes, not permission to lower a global
recognition threshold.

## What v4 supports now

1. Add and validate candidate definitions for both 180 Shuvit directions.
2. Build a candidate Double Flip definition and confusion tests against Flip
   and Phone Flip.
3. Add real recorded replay/feature fixtures for those classes.
4. Preserve the existing v0.2 six-class behavior as regression tests.

Straight Air can be explored but should not yet become a trusted automatic
identity: it lacks intentional misses/look-alike negatives.

## Additional evidence still worth collecting

No more examples are needed immediately for the existing six detector classes.
For the new classes:

- Backside Shuvit 180: add at least 2 intentional misses;
- Double Flip: add at least 3 landed and 1 intentional miss;
- Straight Air: add at least 3 landed and 5 intentional misses/look-alikes;
- Double Phone Flip, Double Reverse Flip, Double Reverse Phone Flip and double
  360 Shuvit variants: v4 has no labelled Trick Lab evidence; target at least 8
  landed across standard/fast-low/high and 5 misses for each before automatic
  recognition is trusted.

After candidate v0.3 parameters freeze, record a separate physical session as
holdout. None of these 118 inspected captures may later be described as an
independent holdout.
