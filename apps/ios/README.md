# Kamikaze native beta

This directory contains the native SwiftUI beta built beside the frozen Expo alpha. It currently includes the app shell, iOS 26 Liquid Glass boundary, pure motion core, a Core Motion device adapter, a live RealityKit phone stage and an experimental automatic detector validated on the reference iPhone. Recorded replay and persistence are the next vertical slice; segmentation/classification still require the schema-v3 separation and physical fixture expansion described in the master plan.

## Requirements

- Xcode 26.6 or compatible Xcode 26 release
- Swift 6
- iOS 26 Simulator runtime for the reference visual build
- iOS 18 or newer on supported physical iPhones

The app prioritizes iOS 26 APIs and uses deliberate Material fallbacks on iOS 18–25.

## Test the motion core

```sh
swift test --package-path apps/ios/Packages/KamikazeMotionCore
```

## Build and test the app

List available destinations first:

```sh
xcodebuild \
  -project apps/ios/Kamikaze/Kamikaze.xcodeproj \
  -scheme Kamikaze \
  -showdestinations
```

Then substitute one available Simulator ID:

```sh
xcodebuild \
  -project apps/ios/Kamikaze/Kamikaze.xcodeproj \
  -scheme Kamikaze \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<SIMULATOR-UUID>' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The current reference destination is an iPhone 17 Pro Simulator. The physical reference device is an iPhone 15 Plus in right-handed grip; production code must not hardcode either model.

## Run on Daniel's iPhone with a free Personal Team

1. Open `apps/ios/Kamikaze/Kamikaze.xcodeproj` in Xcode.
2. Add Daniel's Apple ID in Xcode Settings > Accounts if it is not already present.
3. Select the Kamikaze app target, then Signing & Capabilities.
4. Enable automatic signing and select Daniel's Personal Team.
5. Connect and trust the iPhone, select it as the run destination and press Run.

The development bundle identifier is `tech.sateler.kamikazephone.dev`, leaving `tech.sateler.kamikazephone` available for a future paid team. Free Personal Team provisioning expires after seven days and cannot distribute through TestFlight.

Never commit a Team ID, certificate or provisioning profile. If command-line signing configuration is needed, copy `apps/ios/Kamikaze/Config/Signing.local.xcconfig.example` to `Signing.local.xcconfig` and keep the real file local.

## Export evidence from the Expo alpha

In the Expo alpha, open Me > Settings > Export Alpha Data, save/share the generated JSON and add only reviewed, labelled captures to `fixtures/motion/v2`. Do not commit an unreviewed full personal history dump.

## Current acceptance state

- Expo: 33 deterministic tests pass and TypeScript checks pass.
- Swift package: seven tests pass, including both real Phone Flip fixture decodes plus synthetic low-trick, reset and timeout behavior.
- Native app: command-line build passes on the iOS 26.5 Simulator and as a signed device build.
- Physically validated: native Core Motion at a requested 100 Hz, measured-rate diagnostics, live RealityKit orientation, camera orbit/pinch/reset, Zero Pose and automatic closure of a real attempt.
- Experimental: rule-based trick classification and schema-2 attempt construction. This is not yet a physical accuracy claim.
- Not yet implemented natively: recorded replay transport, saved-attempt persistence, Result/Recent and complete Practice/Locker/Profile/Workshop behavior.

See [`../../docs/NATIVE_BETA_KNOWN_ISSUES.md`](../../docs/NATIVE_BETA_KNOWN_ISSUES.md) before tuning the detector or using its output as a persistent product contract.
