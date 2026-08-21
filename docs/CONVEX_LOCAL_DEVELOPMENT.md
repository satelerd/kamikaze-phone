# Convex local development

This directory is a no-secrets backend workspace. A development-only Convex
project and deployment have been provisioned for the prototype; its generated
`.env.local` selection is ignored by Git. No production deployment or player
data exists, and the iOS package resolution is unchanged.

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

Authentication is deliberately disabled in the current development deployment
(`providers: []`). Once the identity-provider decision is made, configure the
public OIDC issuer and application ID in `auth.config.ts`:

```text
KAMIKAZE_OIDC_ISSUER=https://your-provider.example
KAMIKAZE_OIDC_APPLICATION_ID=your-client-or-service-id
```

The issuer must equal the token `iss` claim and the application ID must equal
the token `aud` claim. Never commit a client secret, private key, deployment
key, ID token or production URL. Use `npx convex dev --once` for this
development deployment; `convex deploy` targets production and is not part of
the prototype workflow.

## iOS package integration (later, explicitly authorized)

The current Xcode target intentionally builds without ConvexMobile. When the
main integrator is ready to connect it:

1. Add `https://github.com/get-convex/convex-swift` to the app target and use
   the current `ConvexMobile` product.
2. Implement a `ConvexTransport` adapter around one process-lifetime
   `ConvexClientWithAuth`.
3. Supply the selected OIDC provider’s refreshed ID token through its
   supported `AuthProvider` implementation.
4. Inject the adapter into `CloudSyncCoordinator`; keep local persistence and
   Play/NativeRunModel independent of sync availability.
5. Put the deployment URL in a local build configuration or runtime injection;
   do not add it to source files or tests.

Convex’s Swift client accepts query/mutation argument dictionaries and
`Decodable` response structs. Its numeric fields need the documented Convex
numeric conversion wrappers when represented in a concrete client model; this
prototype keeps the transport boundary as `CloudJSONValue` so the app target
does not take a package dependency before that integration.

## Tests

Run the existing app tests from `apps/ios/Kamikaze/` with the project’s normal
Xcode command. The new `CloudSync*Tests.swift` cases are deterministic and do
not contact Convex: they cover argument omission, Codable round trips,
idempotent outbox enqueue, persisted retries, bounded backoff, successful
drain, local-only fallback and offline behavior.
