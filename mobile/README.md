# Kamikaze Phone mobile prototype

Expo SDK 54 prototype for real motion capture, fast freefall segmentation, persistent attempt history and reconstructed 3D replay. SDK 54 is intentional because it is the version supported by Expo Go on physical iOS devices from the App Store.

## Run on a physical phone

1. Install Expo Go from the App Store or Play Store.
2. From this directory run `npx expo start --lan`.
3. Scan the QR code with the phone.
4. Open **Lab**, enable motion access, and confirm that the Hz and live energy values move.
5. Return to **Play**, arm one attempt, and test over a bed or another soft surface.
6. Open **Dojo** to replay the measured orientation and revisit saved attempts.

The iOS Simulator and browser do not provide real phone motion. **Simulate phone flip** in Lab verifies the UI and detector without physical hardware.

Use a protective case, begin with low throws, and test over a bed or another soft surface.

## Verification

```bash
npm run typecheck
npm test
```

## Current detection model

- Requests 100 Hz device motion updates.
- Enters flight after 25 ms below 0.28 g.
- Keeps a 300 ms pre-release buffer so short tricks retain their first rotation samples.
- Integrates angular rate by axis during the freefall window.
- Treats the first exit above 0.55 g as a catch candidate.
- Requires 180 ms of post-catch stability before logging the attempt.
- Estimates height from airtime with `h = gT² / 8`.

The thresholds are intentionally visible and will be calibrated from real recordings. The summary classifier remains axis-wise, while Dojo reconstructs the replay orientation with quaternion integration. Learned personal trick templates are the next mathematical step.

See [docs/TECHNICAL_PROTOTYPE.md](docs/TECHNICAL_PROTOTYPE.md) for the body-frame convention, formulas, limitations and physical calibration protocol.
