# Contributing

## Choose one implementation boundary

- Android or cross-platform alpha work: `apps/expo/`
- Native iOS beta work: `apps/ios/`
- Shared, reviewed motion evidence: `fixtures/`
- Historical research only: `archive/`

A normal feature pull request should change one active application. If a detector-contract change requires edits in both apps, explain the compatibility impact and add or update a reviewed fixture first.

## Branches

Create a feature branch from the current integration branch and use a platform prefix, for example:

```sh
git switch -c android/<feature-name>
git switch -c ios/<feature-name>
```

Do not make a copied `max-version`, `daniel-version` or `v4` directory. Branches isolate concurrent work; folders isolate runtimes and build systems. This keeps Android contributions from touching the Xcode project while still allowing both products to consume the same motion evidence.

## Verification

For Expo changes:

```sh
cd apps/expo
npm run typecheck
npm test
```

For the native motion package:

```sh
swift test --package-path apps/ios/Packages/KamikazeMotionCore
```

For the iOS app, use the shared `Kamikaze` scheme in `apps/ios/Kamikaze/Kamikaze.xcodeproj`.

## Historical versions

Use the tags and worktree commands in `docs/HISTORY.md`. Never modify an existing milestone tag; branch from it when an experiment genuinely needs to continue.
