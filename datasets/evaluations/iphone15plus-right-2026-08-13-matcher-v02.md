# Matcher v0.2 evaluation — iPhone 15 Plus, right hand

Source dataset SHA-256:
`6c2c9c41cb3500cf59706bbda88b16d3b4784971039716f3abe5dd9f34a23bf9`.

The split was frozen before changing `TrickCatalog` or `TrickMatcher`:

- development: 11 standard/high landed captures;
- holdout: 6 fast/low landed captures and 7 guided negative controls.

The holdout is a first-session regression gate, not a production accuracy
claim. It represents one iPhone 15 Plus, one right-handed player, one case and
one recording session.

## Before

`trick-catalog-v0.1-uncalibrated` represented Flip on X, Phone Flip as a pure
Y rotation and Shuvits as 180 degrees.

| Set | Recognized landed with correct identity | Misses not celebrated |
|---|---:|---:|
| Development | 0/11 | n/a |
| Holdout | 0/6 | 5/7 |

## After

`trick-catalog-v0.2-iphone15plus-right` and
`rule-matcher-v0.2-angular-path` use signed rotation together with normalized
angular-path distribution, duration and a conservative evidence-stability
gate.

| Set | Recognized landed with correct identity | Misses not celebrated |
|---|---:|---:|
| Development | 11/11 | n/a |
| Holdout | 6/6 | 7/7 |

The six holdout landed captures independently resolve as Flip, Reverse Flip,
Phone Flip, Reverse Phone Flip, Backside Shuvit and Frontside Shuvit. Phone
Flip is the product name for the phone equivalent of a 360 Flip: its cross-axis
angular path distinguishes it from the comparatively axial Flip even when the
final signed X/Z rotations cancel.

`postCatchStability` is used only as a conservative evidence gate at its
extreme low end. It is not yet a calibrated landed probability, and the UI's
numeric fit remains a rule fit rather than a confidence percentage.

## Required next validation

Do not tune further against this holdout. Record a second session and report
results without changing v0.2 first. The next dataset must add no-case samples,
left hand, at least one additional recent iPhone model, ordinary handling and
more naturally occurring misses.
