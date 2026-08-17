# Dataset audit — native player feedback — 2026-08-16

Source: `fixtures/motion/v3/datasets/player-feedback-2026-08-16.json`

SHA-256: `4534d39236a87c1a10098b38bc7d530913af8aee9c2434d8b8d8a368ca9f9748`

## Contents

| Human label | Landed | Missed | Total |
|---|---:|---:|---:|
| Backside 360 Shuvit | 7 | 0 | 7 |
| Frontside 360 Shuvit | 6 | 0 | 6 |
| Flip | 3 | 0 | 3 |
| Reverse Flip | 4 | 1 | 5 |
| Phone Flip | 7 | 0 | 7 |
| Reverse Phone Flip | 5 | 1 | 6 |
| Double Phone Flip | 2 | 0 | 2 |
| **Total** | **34** | **2** | **36** |

All 36 entries retain raw schema-v3 samples and are labelled automatic
captures. The payload reports right-hand grip and portrait orientation. Device
model identifier and OS version were not populated by the recorder.

## What this evidence supports

- regression/error analysis for the validated v0.2 identity classes;
- deterministic replay tests built from real native samples;
- development of a transparent motion-quality score shape;
- a **candidate**, not production, Double Phone Flip reference. Its two landed
  captures are unusually consistent: net Y rotation is 941.8° and 942.9°,
  with durations 1,734.8 ms and 1,625.3 ms.

## What it does not support

- a landing classifier or a landed/missed threshold: there are only two misses;
- left-hand semantics;
- 180° Shuvits, Double Flip, Double Reverse Flip or Double Reverse Phone Flip;
- per-device axis/bias/gain calibration: these are gameplay throws, not known
  ±90°/±360° calibration movements;
- an independent accuracy result after tuning against this dataset.

## Required next collection

1. Keep v0.2 frozen while using this file as development evidence.
2. For every new class, collect at least 8 landed development examples across
   standard, fast/low and high throws, plus at least 5 intentional misses or
   look-alike negatives.
3. After candidate parameters freeze, record a different session as holdout;
   never move these same captures into the holdout split.
4. Record Express/Full calibration choreography separately: X/Y/Z, both signs,
   ±90° and ±360°, with the phone held still before and after each movement.
5. Populate hardware model, OS version and calibration profile ID in all future
   captures.

## Score implication

Game Score v1 may expose deterministic motion quality (completion, purity,
post-catch stability and flow), but automatic **landing** remains unverified.
Human `missed` must override awarded score, and identity FIT must continue to
be shown separately from score.
