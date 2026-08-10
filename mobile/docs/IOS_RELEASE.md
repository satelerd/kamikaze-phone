# iOS release path

Kamikaze stays in Expo/React Native for its first release. EAS produces the signed native iOS binary; Swift modules are reserved for isolated features such as ReplayKit video export or WidgetKit.

## Build profiles

- `development`: custom development client for physical-device debugging.
- `preview`: ad hoc release-like build for registered iPhones.
- `production`: App Store/TestFlight binary with an automatically incremented build number.

## Local validation

```bash
npm ci
npm run typecheck
npm test
npx expo export --platform ios
```

## First development build

```bash
npx eas-cli@latest login
npx eas-cli@latest init
npm run build:ios:development
```

The iPhone must be registered in the Apple provisioning profile for an internal iOS build. Use `npx eas-cli@latest device:create` if EAS requests it.

## TestFlight

1. Create the App Store Connect record for `tech.sateler.kamikazephone`.
2. Add the App Store Connect app ID to the `submit.production.ios.ascAppId` field in `eas.json`.
3. Run `npm run build:ios:production`.
4. Run `npx eas-cli@latest submit --platform ios --profile production`.
5. Assign the processed build to an internal TestFlight group.

## Release gates

- Core Play capture works after a cold launch and after denying/re-enabling motion permission.
- Attempts and calibration persist across restarts.
- Practice and saved-attempt replay animate and scrub correctly.
- Developer tools are hidden from the normal player path.
- Safety onboarding recommends a case, a clear area, a low throw and a soft surface.
- Privacy policy and support URLs are live and reachable.
- App Store privacy, age-rating and export-compliance answers are complete.
- Store screenshots and review notes accurately describe the physical gameplay and its safety guidance.

## Known prototype blocker

Practice and saved-attempt replay can remain visually static in Expo Go. Re-test this first in the development client; do not promote the build to external TestFlight until the native build either confirms the fix or provides a reproducible trace.
