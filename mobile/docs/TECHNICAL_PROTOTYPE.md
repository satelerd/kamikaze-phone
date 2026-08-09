# Kamikaze Phone — technical prototype 01

## Product hypothesis

The phone already contains the minimum useful IMU: a three-axis accelerometer and a three-axis gyroscope. A first version can therefore segment a throw, measure its airborne rotation and classify a small vocabulary of tricks without a camera or external hardware.

This does **not** mean that every trick can be named reliably from day one. The reliable route is:

1. detect release and catch;
2. save a clean motion window;
3. reconstruct rotation in the phone body frame;
4. let the rider correct the proposed label;
5. learn templates or a model from real, labelled attempts.

That correction loop is also how Skategrounds describes improving its own detector.

## Body-frame convention

- **X:** across the short edge of the screen.
- **Y:** bottom-to-top along the long edge.
- **Z:** perpendicular to the screen, pointing out of it.

The app normalizes Expo's platform-specific `alpha/beta/gamma` ordering into this XYZ convention. This matters because the iOS and Android native implementations do not expose those labels in the same order.

## What prototype 01 does now

The requested interval is 10 ms (100 Hz). Every sensor sample is processed; React rendering is throttled to 20 Hz so animation work does not throw away detector data.

The state machine is:

```text
IDLE → ARMED → AIRBORNE → SETTLING → COMPLETE
```

- **Release:** acceleration magnitude remains below `0.28 g` for at least `25 ms`.
- **Prebuffer:** the detector retains `300 ms` before release and retrospectively integrates the confirmed freefall onset.
- **Airborne rotation:** angular velocity is integrated per body axis with the trapezoidal rule.
- **Catch candidate:** acceleration exits freefall above `0.55 g`.
- **Confirmed catch:** acceleration returns to `0.68–1.38 g` and angular speed below `90°/s` for `180 ms`.
- **Timeout:** an attempt leaves flight after `2600 ms` even if a clean catch was not observed.
- **Estimated height:** `h = gT²/8`, using measured airtime `T`.

The height number is deliberately labelled **estimated**. The formula assumes a roughly symmetric ballistic arc and that release and catch occur at similar heights. Double-integrating phone acceleration is not a good primary height estimator because gravity-removal error and bias drift grow very quickly.

## Provisional trick vocabulary

The current deterministic classifier is useful for calibration, not a final definition of the sport.

| Provisional label | Signal rule |
| --- | --- |
| Straight Air | little rotation on every axis |
| Front / Back Flip | one turn around X |
| Kickflip / Heelflip | one turn around Y, direction selected by grip |
| Backside / Frontside Shuvit | half turn around Z, direction selected by grip |
| Phone Flip | one Y edge flip plus one full Z spin; 360 Flip skate analogue |
| Reverse Phone Flip | reverse Y edge flip plus reverse Z spin; Laser Flip analogue |
| Kamikaze Flip | X flip plus a half Z spin |

Directional names remain provisional until the right/left grip convention is verified against Daniel's labelled throws.

The 3D replay visualizes measured orientation only. Its phone position is intentionally locked because IMU-only translation would currently be a fabricated trajectory. Every replay begins from a phone lying screen-up on the reference grid.

## The mathematical upgrade path

Axis-wise angle totals are enough for the basic classifier, but rotations do not commute. Replay reconstruction now also integrates the gyroscope into a unit quaternion:

```text
q(k+1) = normalize(q(k) ⊗ exp(½ ω(k) Δt))
```

That gives a continuous orientation path without Euler-angle wrap or gimbal lock. From that path we can derive:

- net orientation change;
- total rotation path;
- dominant body axis over time;
- direction reversals and multi-axis coupling;
- peak angular speed and time-to-peak;
- landing face and catch quality.

The classifier should progress in three stages:

1. **Rules:** transparent thresholds for the first physical tests.
2. **Templates:** compare normalized angular-velocity curves using correlation or dynamic time warping.
3. **On-device model:** train on corrected real attempts only after the dataset contains enough variation across devices, cases, hands and throw styles.

## Physical calibration session

Test over a bed, use a protective case and start below eye height.

1. Place the phone still for five seconds and confirm approximately `1.00 g`, low `°/s`, and a stable measured rate.
2. Rotate it slowly once around each axis and verify that only the intended Lab bar dominates.
3. Record 10 straight throws without rotation.
4. Record 10 examples of each intended trick and 5 deliberate misses.
5. For every attempt, preserve raw samples from 300 ms before release through 500 ms after catch and attach the human label.
6. Plot distributions for airtime, integrated angle, peak gyro and catch impulse before changing thresholds.

Build 0002 stores up to 50 attempts, including raw samples, in on-device SQLite and can replay their measured orientation. The next implementation slice should add export plus a “correct this trick” control. That dataset is more valuable than prematurely training a model on synthetic signals.

## References

- Expo SDK 54 DeviceMotion: https://docs.expo.dev/versions/v54.0.0/sdk/devicemotion/
- Skategrounds: https://skategrounds.tech/
- Wheatland et al., *The mobile phone as a free-rotation laboratory*: https://doi.org/10.1119/10.0003380
- Groh et al., *IMU-based Trick Classification in Skateboarding*: https://www5.cs.fau.de/Forschung/Publikationen/2015/Groh15-ITC.pdf
