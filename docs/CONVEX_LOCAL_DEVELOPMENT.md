# Convex local development

This directory is a no-secrets backend workspace. A development-only Convex
project and deployment have been provisioned for the prototype; its generated
`.env.local` selection is ignored by Git. No production deployment or player
data exists. The iOS package resolution is committed so every checkout uses
the same Clerk and Convex SDK versions.

## Backend

```sh
cd services/convex
npm install
npx convex dev
```

The first `npx convex dev` generates `convex/_generated/` locally; those
generated bindings are committed so a clean checkout can typecheck the server.
Keep the CLI running while editing schema/functions. The typecheck script is:

```sh
npm run typecheck
```

Authentication uses Clerk's Convex integration. Activate the Convex integration
for the linked Clerk application in the Clerk Dashboard, then copy its public
Frontend API URL. Set that URL on the Convex development deployment (the iOS
`.env` is not read by the backend):

```sh
npx convex env set CLERK_JWT_ISSUER_DOMAIN 'https://your-clerk-frontend-api.example'
npx convex dev --once
```

The checked-in `convex/auth.config.ts` maps that issuer to the Convex audience
`convex`. The value must match the JWT `iss` claim exactly. Do not put a Clerk
secret key, private key, deployment key or ID token in this repository or in the
iOS target. Use `npx convex dev --once` for this development deployment;
`convex deploy` targets production and is not part of the prototype workflow.

## iOS package integration

The Cloud layer contains a conditional, authenticated adapter in
`Cloud/ClerkConvexTransport.swift`. The app target selects these official
products (the exact package versions are recorded in `Package.resolved`):

1. `https://github.com/get-convex/convex-swift` → `ConvexMobile`.
2. `https://github.com/clerk/clerk-convex-swift` → `ClerkConvex`.
3. `https://github.com/clerk/clerk-ios` → `ClerkKit` when it is not already
   available transitively.

At the app composition boundary, call `Clerk.configure(publishableKey:)` with
the publishable key only, obtain the deployment URL from
`KamikazeIdentityConfiguration.convexDeploymentURL`, and construct
`ConvexCloudClient.clerk(deploymentURL:)`. Keep the returned transport/client
alive for the process lifetime. Call `loginFromCache()` after Clerk restores a
session, observe `transport.authState`, and use `login()` only from the actual
Clerk sign-in flow. The adapter obtains and refreshes tokens through
`ClerkConvexAuthProvider`; app code never handles a secret or manually copies a
JWT. Inject the returned `remote` into `CloudSyncCoordinator` while keeping
local persistence and Play/NativeRunModel independent of sync availability.

The deployment URL is runtime/build configuration, not a source constant or a
test fixture. The conditional imports leave the local-first target usable when
the products are not selected.

Convex’s Swift client accepts query/mutation argument dictionaries and
`Decodable` response structs. Its numeric fields need the documented Convex
numeric conversion wrappers when represented in a concrete client model; this
prototype keeps the domain boundary as `CloudJSONValue` and uses the official
`ConvexEncodable` bridge only inside the Clerk adapter.

## Tests

Run the existing app tests from `apps/ios/Kamikaze/` with the project’s normal
Xcode command. The new `CloudSync*Tests.swift` cases are deterministic and do
not contact Convex: they cover argument omission, Codable round trips,
idempotent outbox enqueue, persisted retries, bounded backoff, successful
drain, local-only fallback and offline behavior. A simulator build with the
resolved Clerk/Convex products is the useful compile check for the conditional
adapter; no network deployment is required.

Official references:

- [Clerk native iOS Convex integration](https://clerk.com/docs/ios/reference/native-mobile/integrations/convex)
- [Convex Swift client](https://docs.convex.dev/client/swift/overview)
- [Clerk Convex Swift package](https://github.com/clerk/clerk-convex-swift)
