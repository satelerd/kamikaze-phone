# Kamikaze: Phone Flip

Kamikaze: Phone Flip is a physical phone-trick game. The repository intentionally keeps the cross-platform Expo alpha, the native iOS beta and the original web exploration together without coupling their build systems.

## Repository map

| Path | Status | Purpose |
| --- | --- | --- |
| [`apps/expo/`](apps/expo/README.md) | Active alpha | React Native/Expo game, current Expo Go build and the main Android contribution track. |
| [`apps/ios/`](apps/ios/README.md) | Active beta | Native SwiftUI/RealityKit/Core Motion rewrite for iOS 18+, prioritizing iOS 26. |
| [`archive/web-prototype/`](archive/web-prototype/README.md) | Archived | Original browser-based sensor/game exploration. Kept runnable, but not under active product development. |
| [`fixtures/`](fixtures/motion/v2/README.md) | Shared | Reviewed motion captures used to verify detector and replay parity across implementations. |
| [`docs/HISTORY.md`](docs/HISTORY.md) | Reference | Timeline of milestones, tags, branches and instructions for opening an old version safely. |

## Run the current implementations

Expo alpha:

```sh
cd apps/expo
npm install
npx expo start --lan
```

Native iOS beta:

```sh
open apps/ios/Kamikaze/Kamikaze.xcodeproj
```

The native motion core can also be tested without Xcode:

```sh
swift test --package-path apps/ios/Packages/KamikazeMotionCore
```

## Contribution boundaries

Each application owns its UI, platform integrations and build configuration. Cross-platform evidence belongs in `fixtures/`; it should not be copied into either app. A contributor working on Android can branch from the current repository and limit changes to `apps/expo/`, while native iOS development continues independently in `apps/ios/`.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) before changing shared detector behavior or fixture formats.
