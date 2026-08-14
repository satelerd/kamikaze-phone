# Native motion dataset protocol

Reference configuration for the first dataset: iPhone 15 Plus, portrait, right hand. Use a protective case and a clear soft area.

The recorder captures evidence; the automatic detector only adds a proposal. Before sharing a recording, the player supplies the intended label and outcome. A low detector confidence is useful evidence, but it is not the ground-truth label.

## Canonical labels

- `phone-flip`
- `reverse-phone-flip`
- `double-phone-flip`
- `double-reverse-phone-flip`
- `flip`
- `reverse-flip`
- `double-flip`
- `double-reverse-flip`
- `frontside-shuvit-180`
- `backside-shuvit-180`
- `frontside-360-shuvit`
- `backside-360-shuvit`
- `straight-air`
- `unknown` / `no-attempt`

Use **Shuvit** as the canonical skate spelling. An unqualified Shuvit is 180°;
larger rotations always include their degrees. Dataset v1 incorrectly stored the
physically measured 360° classes as `frontside-shuvit` / `backside-shuvit`.
Decoders preserve those legacy IDs as 360 Shuvits; all new exports use explicit
degree-bearing IDs. `FS` and `BS` are display abbreviations only after hand and
axis semantics have been physically validated.

Double Flip and Double Phone Flip labels are collection-only until independent
physical sessions establish their angular path and holdout accuracy. Do not add
synthetic matcher targets and describe them as calibrated detection.

## Capture variants

Each core trick ultimately needs 20 attempts:

| Variant | Count | Meaning |
|---|---:|---|
| low / fast | 8 | compact throw with a quick angular burst |
| normal | 8 | comfortable representative execution |
| high / freefall | 4 | highest safe practical throw |

Also capture 12 Straight Air attempts and 30 negatives: ordinary handling, shakes, in-hand orientation changes, partial rotations, intentional failures and aborted throws. Record one separate ten-minute ordinary-handling session for false-trigger evaluation.

## Session and split rules

- Keep attempts from one continuous session in the same split.
- For each 20-attempt core class: 12 train, 4 validation and 4 holdout.
- Do not tune thresholds using holdout captures.
- Record case/no-case, hand, intended trick, outcome and rhythm for every capture.
- Never overwrite a raw file or relabel it silently. A correction is a new judgement attached to the same evidence.

## First short device pass

Before collecting the full matrix, verify export with:

1. one normal Front Flip;
2. one fast/low Front Flip;
3. one high Front Flip;
4. one Back Flip;
5. one FS Shuvit and one BS Shuvit;
6. two intentional failures;
7. one ordinary in-hand movement marked `no-attempt`.

Stop if the exported file lacks attitude, gravity, user acceleration, timestamps, sample count, device context or a checksum. The full session only starts after these files decode and replay deterministically in MotionCore.

## Confidence hypothesis

The 2026-08-12 physical smoke test suggested malformed attempts often scored below 70%, while successful attempts were higher. Treat a provisional `75–80%` miss/unknown boundary as a product hypothesis only. The current confidence value is rule-fit, not probability. The final boundary must be selected from session-separated validation data and reported once against untouched holdout sessions.
