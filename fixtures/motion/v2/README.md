# Motion fixtures v2

This directory preserves immutable Expo-alpha evidence for TypeScript/Swift parity tests. Fixture payloads keep their original schema and samples; corrections belong in metadata or a newer fixture, never as silent edits to the capture.

## Current real-device set

The first two labelled captures were recorded by Daniel with a right-handed grip. The reference device is an iPhone 15 Plus; the legacy payload itself did not record hardware or OS metadata, so that context is explicitly marked as user-confirmed in `manifest.json`.

- `iphone15plus-right-phone-flip-001.json`
- `iphone15plus-right-reverse-phone-flip-001.json`

Both files use `kpf-labelled-capture-v1` and contain a complete `DetectedAttempt.schemaVersion = 2`, including every recorded motion sample.

## Rules

- Never treat synthetic data as physical-device acceptance evidence.
- Never overwrite a fixture when detector output changes.
- Verify SHA-256 before using a copied/exported fixture.
- Record grip, device, provenance and expected label in the manifest.
- Add Straight Air, both shuvits, Front/Back Flip, misses and axis calibration captures through the alpha export action as soon as they are available.
