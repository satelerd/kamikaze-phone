# Native beta checkpoint — known issues

Checkpoint: `native-beta-device-detector-v0.1.0`

Reference hardware: iPhone 15 Plus, right-handed grip, iOS 26.5.

This checkpoint proves that the native app can stream Core Motion, render the live phone and automatically close a real attempt. It is intentionally not a production detector or a complete game loop.

## Motion and classification

- The detector and classifier are still one transitional type. Section 2 separates segmentation from trick naming.
- Sensor ingestion currently reaches `LiveMotionModel` on the MainActor. `CoreMotionSource` buffers only the newest 16 frames, so UI/rendering pressure could drop evidence silently. The capture actor and gap/drop diagnostics are Section 2 gates.
- Classification uses integrated per-axis thresholds without a physical calibration profile, axis-purity feature, candidate ranking or `Unknown` decision.
- The current combined-axis rule can confuse a shuvit with a 360/Laser-family trick when Y-axis cross-talk is large. Do not tune this from synthetic data; capture labelled physical shuvits first.
- Only Phone Flip and Reverse Phone Flip have reviewed real fixtures. Front/Back, both shuvits, Straight Air, misses and normal handling still need physical evidence.
- The synthetic shuvit test proves low-motion capture closure, not the canonical 180-degree trick definition or physical classification accuracy.
- Duplicate/decreasing timestamps and sample gaps are not yet represented explicitly in the schema.

## Attempt semantics

- Native attempts still use the Expo schema-2 compatibility type. Schema 3 must separate raw and derived values and include device, grip, orientation, calibration and algorithm versions.
- For gyro-triggered low tricks, `releaseTimestampS` includes a pre-trigger handle and `catchTimestampS` follows a quiet window. The displayed value is therefore labelled **motion duration**, not physical airtime.
- `peakCatchG` now preserves the strongest acceleration in the active window, but the final schema should identify motion end, catch impulse and settled state separately.
- `confidence` is a rule-fit indicator, not a calibrated probability or game score. The checkpoint UI labels it `CONF`; a versioned ScoreEngine remains future work.

## Product completeness

- Captures are not persisted. Closing or reinstalling the app loses the result.
- There is no native Result/Recent detail or recorded replay transport yet.
- Practice, Profile, Locker and Workshop remain structural shells or local previews.
- Manual capture, express/full calibration, custom tricks and lines are not implemented natively.
- Simulator validates UI and fixture playback only; it cannot validate real sensor delivery.

## Physical smoke-test protocol

Use a case and a clear, soft area.

1. Open Play and confirm `MOTION: LIVE` plus a measured rate.
2. Hold the phone naturally and tap **Zero Pose**.
3. Tap **Start Session** and verify `SESSION / ARMED`.
4. Perform one low Phone Flip and hold the catch steady.
5. Verify `MOTION → LANDING → LANDED/result` without a high throw.
6. Repeat with a higher throw.
7. Start and cancel a session; verify it returns to Ready.
8. Start a trick, change tabs, return to Play and verify no old attempt completes.
9. Leave an active motion unsteady; verify the safety timeout closes it instead of hanging indefinitely.

Record failures with the visible phase, expected trick, actual label, case/no-case and approximate speed/height. Do not overwrite an old fixture when correcting a label.

The completed baseline session is recorded at [`device-sessions/2026-08-12-iphone15plus-right-baseline.md`](./device-sessions/2026-08-12-iphone15plus-right-baseline.md).
