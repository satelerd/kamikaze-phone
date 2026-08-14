# Matcher v0.2 independent validation — session 2

Source cumulative dataset SHA-256:
`3320f6a879079ef0e6db84b7bb0839a7eafbbd53c9ff39c2004ee562720e4bf1`.

The raw export contains 62 captures. The frozen holdout contains every capture
absent from the first v1 dataset: 25 captures total. Twenty-four are the second
guided pass and one is an additional independent standard Flip recorded after
the first export. None was used to tune `trick-catalog-v0.2-iphone15plus-right`
or `rule-matcher-v0.2-angular-path`.

## Result

| Measure | Result |
|---|---:|
| Landed attempts recognized with correct identity | 19/19 |
| Intentional misses not recognized as landed tricks | 6/6 |
| Standard landed condition | 7/7 |
| High/freefall landed condition | 6/6 |
| Fast/low landed condition | 6/6 |

| Trick | Correct landed identity | Miss not celebrated |
|---|---:|---:|
| Flip | 4/4 | 1/1 |
| Reverse Flip | 3/3 | 1/1 |
| Phone Flip | 3/3 | 1/1 |
| Reverse Phone Flip | 3/3 | 1/1 |
| Backside Shuvit | 3/3 | 1/1 |
| Frontside Shuvit | 3/3 | 1/1 |

Landed identity FIT ranged from 0.843 to 0.956 (mean 0.903). Intentional-miss
top-candidate FIT ranged from 0.555 to 0.760 (mean 0.642). The highest miss
still remained `review`, demonstrating why FIT alone cannot be treated as a
landing probability: candidate margin, evidence quality and post-catch
stability also gate recognition.

All six intentional misses produced `review`, not `recognized`. Their proposed
identity is diagnostic only and is not scored as ground truth.

## Evidence quality

- iPhone model identifier: `iPhone15,5` (iPhone 15 Plus).
- iOS 26.0 build `23A340`; right hand; portrait reference frame.
- 9,044 new raw samples; 217–776 per capture (mean 361.76).
- Requested 100 Hz; measured 100.256–100.335 Hz (mean 100.305 Hz).
- Zero timestamp gaps, sequence gaps, missing attitudes or quality-flagged
  samples in the 25 new captures.
- All 62 embedded payloads in the cumulative export passed schema, attempt ID,
  sample-count and SHA-256 validation.
- A tampered-copy smoke test was rejected by the evaluator at the source
  SHA-256 gate before classification.
- Motion bursts ranged from 604 ms to 2,777 ms (mean 1,041 ms).

## Scope and decision

This validates v0.2 for one right-handed player on one iPhone 15 Plus across
guided standard, high and fast/low throws. It is strong enough to freeze v0.2
for the current beta and stop tuning on these two sessions.

It is not a production-wide accuracy claim. The new captures record case state
as `unknown`; misses are guided negative controls rather than organic play; and
left hand, other devices and other players remain unvalidated. The next useful
evidence should come from normal Play corrections through `NOT QUITE?`, then a
separate left-hand/device/player matrix. This session must remain a permanent
regression holdout.
