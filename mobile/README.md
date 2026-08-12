# Kamikaze: Phone Flip

Expo SDK 54 prototype for a physical phone-trick game. The current app combines the proven motion-capture and quaternion replay system with a gameplay-first experience: onboarding, live 3D Play stage, automatic or manual capture, immediate trick results, guided Practice, a skin Locker and a local player Profile.

The preserved technical testing baseline is Git tag `testing-v0.2.0`. Calibration and raw sensor tools remain available inside **Me → Open Sensor Workshop**.

## Run on a physical phone

1. Install Expo Go from the App Store or Play Store.
2. From this directory run `npx expo start --lan`.
3. Scan the QR code with the phone.
4. Complete the short onboarding and enable motion access.
5. In **Play**, keep the phone low and test over a bed or another soft surface.
6. Use **Manual** capture or **Practice** when collecting deliberate labelled tricks.

The iOS Simulator and browser do not provide representative real-phone motion. A protective case and a soft testing surface are strongly recommended.

## Product prototype

- **Play:** live 3D phone, Flux Halo state feedback, automatic/manual recording and immediate result replay.
- **Practice:** ideal trick preview and three-rep guided capture.
- **Locker:** local points and selectable phone skins.
- **Me:** totals, streak, records, 12-week activity grid, recent attempts and developer tools.
- **Onboarding:** optional, replayable and contextual to the motion permission.
- **Liquid Glass:** native on supported iOS versions, with a deliberate dark fallback elsewhere.

See [docs/GAME_EXPERIENCE_PROTOTYPE.md](docs/GAME_EXPERIENCE_PROTOTYPE.md) for the product thesis, core loop, information architecture, visual system, scoring model and production risks. The detector mathematics and coordinate conventions remain documented in [docs/TECHNICAL_PROTOTYPE.md](docs/TECHNICAL_PROTOTYPE.md).

## Verification

```bash
npm run typecheck
npm test
npx expo export --platform ios
```

## Native builds and TestFlight

The project uses EAS profiles for a custom development client, registered-device previews and TestFlight/App Store production builds. See [docs/IOS_RELEASE.md](docs/IOS_RELEASE.md) for commands, release gates and the App Store Connect handoff.

## Current detection model

- Requests 100 Hz device-motion updates.
- Keeps a pre-release buffer so short, low tricks retain their first rotation samples.
- Segments automatic attempts from release, catch-candidate and post-catch stability.
- Supports full-surface manual capture for labelled trick training.
- Integrates angular velocity into quaternion replay frames.
- Matches attempts against the editable trick catalog and learned examples.
- Persists attempts and calibration locally for later replay and comparison.

The next production phase should version every detector/scoring change, pause sensors and GL rendering off-screen, formalize grip/orientation settings and validate the automatic low-airtime trigger against a larger labelled dataset.
