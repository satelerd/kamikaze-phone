# Kamikaze native beta

This directory contains the lead SwiftUI implementation built beside the Expo
alpha. The current beta includes native Core Motion capture and detection,
RealityKit live/replay scenes, persistent attempts, Play and Practice,
customizable phone models, accounts/sync foundations, a paged 3D social feed and
an experimental camera-run editor/exporter.

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
- Swift motion package: 48 deterministic tests cover schema v3, segmentation,
  replay, evidence quality and provisional matching.
- Native app: command-line builds pass on the iOS Simulator; signed-device
  installation and sensor behavior are validated on the reference iPhone.
- Physically exercised: automatic capture closure, result/recent replay,
  Practice, camera preview and front/rear source recording.
- Release-candidate validation: slow-motion export, Photos save, native export
  cards, new real-device meshes and paged feed interaction still require the
  final physical-device checklist for each candidate.
- Experimental: trick identity/scoring, community evidence workflows and social
  cloud behavior remain beta contracts rather than production accuracy claims.

See [`../../docs/NATIVE_BETA_KNOWN_ISSUES.md`](../../docs/NATIVE_BETA_KNOWN_ISSUES.md) before tuning the detector or using its output as a persistent product contract.
