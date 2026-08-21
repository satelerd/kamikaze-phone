# Convex sync prototype

Status: bounded initial prototype. Its schema/functions are live on a
development-only deployment; there is no production deployment, auth provider
or player data. The implementation lives under `services/convex/` and
`apps/ios/Kamikaze/Kamikaze/Cloud/`.

## What is synced

The native app remains useful without an account or a network connection. Its
existing local repositories own raw motion evidence and local interpretation.
The Convex projection contains only:

- `users`: the authenticated OIDC issuer/subject and lifecycle timestamps;
- `profiles`: display name, joined date, optional bio and profile visibility;
- `attemptSummaries`: the small `AttemptSummaryV1` projection used by history
  and statistics (never the raw sample payload);
- `media`: Convex Storage IDs plus metadata for replay/thumbnail/avatar media;
- `socialVisibility`: an explicit per-attempt private/friends/public decision;
- `syncReceipts`: short-lived idempotency receipts for retried mutations.

`friends` is reserved for a future relationship table. Until that exists, the
public feed only returns `public` rows and owner queries can see their own
private/friends rows.

## Server contract

The functions are intentionally small and owner-scoped:

| Function | Purpose |
| --- | --- |
| `users:ensureCurrentUser` | Provision the current OIDC identity and private profile, idempotently. |
| `users:me` | Read the current user/profile only. |
| `users:deleteMyAccount` | Hard-delete the current user, summaries, media, visibility rows and storage objects. |
| `profiles:mine` / `profiles:upsertMine` | Read or idempotently update the current profile. |
| `attemptSummaries:listMine` / `getMine` | Read only the current owner’s summary projection. |
| `attemptSummaries:upsert` | Upsert by `(userId, attemptID)`, preserving an existing human review. |
| `attemptSummaries:deleteMine` | Idempotently delete one summary and its owned media/share row. |
| `media:generateUploadURL` | Generate a short-lived upload URL after authentication. |
| `media:mine` / `media:register` / `media:deleteMine` | Owner-only media metadata and Storage lifecycle. |
| `social:mine` / `setVisibility` | Owner-only visibility controls. |
| `social:publicAttempt` / `publicFeed` | Read only explicitly public attempts and public media. |

Every mutation that can be retried from the mobile outbox accepts a
`mutationID`. The entity write and `syncReceipts` insert happen in the same
Convex transaction. Replaying the same ID returns the original acknowledgement;
reusing it for a different operation throws. Upserts also have stable client
keys (`attemptID` and `mediaKey`) so a new app launch cannot create duplicate
rows when the caller intentionally replays a local command.

All public functions derive ownership from `ctx.auth.getUserIdentity()` and
never accept a caller-provided `userId` for owner writes. A missing identity is
an unauthenticated error, and an authenticated identity must first be
provisioned by `users:ensureCurrentUser`.

## iOS boundary and local-first behavior

`CloudSyncOperation` is a serializable command for one bounded mutation.
`FileCloudOutbox` stores those commands in Application Support (or an injected
test directory), keeps the same mutation ID across retries, and applies capped
exponential backoff. `CloudSyncCoordinator` drains a bounded foreground batch;
it does not run a background upload loop, block capture, or delete an entry on a
transient error. The states are `localOnly`, `offline`, `idle`, `syncing`,
`needsAuthentication` and `failed`.

`ConvexCloudClient` depends on the small `ConvexTransport` protocol, not on
`ConvexMobile`. That keeps the current target compiling before the Xcode
package dependency and runtime deployment URL are wired in. The eventual adapter should wrap
one process-lifetime `ConvexClientWithAuth` and map its `mutation`/`subscribe`
calls to the protocol. The Beta tab includes a product-facing account/sync
prototype, but it labels identity honestly and never pretends its Sign in with
Apple preview is a real session. `NativeRunModel` remains independent from
sync availability.

Media bytes are deliberately a separate follow-up: call
`media:generateUploadURL`, POST the file, then enqueue `media:register` with the
returned Storage ID. The outbox currently syncs registration metadata, not raw
motion samples.

## Authentication recommendation

Use Sign in with Apple as the iOS-facing sign-in experience, but put a
supported OIDC provider between the Apple credential and Convex for the first
production path:

1. `AuthenticationServices` obtains the Apple authorization result and nonce.
2. Auth0 (recommended first for the existing Swift client support) or Clerk
   verifies Apple and issues the OIDC ID token used for Convex.
3. The app supplies that refreshed ID token through the provider’s Convex
   Swift integration and constructs `ConvexClientWithAuth`.
4. The first authenticated call is `users:ensureCurrentUser`; all subsequent
   functions derive ownership from the verified identity.

Convex’s current Swift docs document `ConvexMobile`, a process-lifetime
`ConvexClient`, `ConvexClientWithAuth`, Auth0 support and a Clerk integration;
the Swift package’s 0.8 auth lifecycle also allows providers to push refreshed
tokens into the client. Convex’s auth docs state that OIDC issuer (`iss`) and
application ID (`aud`) must match the configured provider exactly.

If avoiding a third party is more important than time-to-production, use a
small server-side Apple broker instead: verify Apple’s authorization code and
nonce, mint a short-lived OIDC JWT with a stable `sub`, exact `iss`/`aud`,
`iat`/`exp`, and publish a JWKS endpoint. Configure that issuer in
`convex/auth.config.ts` and implement a custom Swift `AuthProvider` that
refreshes tokens. Never mint or sign that JWT in the iOS app. Do not pass
invented credentials or production IDs into this repository.

Direct Apple-token validation by Convex is possible only after confirming the
Apple token’s exact issuer, audience and refresh behavior for the chosen App
ID/Service ID. It is not the default recommendation for this prototype.

References:

- [Convex iOS & macOS Swift client](https://docs.convex.dev/client/swift/overview)
- [Convex Swift type conversion](https://docs.convex.dev/client/swift/data-types)
- [Convex authentication overview](https://docs.convex.dev/auth/overview)
- [Custom OIDC provider configuration](https://docs.convex.dev/auth/advanced/custom-auth)
- [Apple AuthenticationServices](https://developer.apple.com/documentation/authenticationservices)

## Privacy and deletion

- Raw motion samples stay local in the existing Application Support store; the
  cloud schema only carries summary fields.
- Media is private by default. Convex Storage URLs are bearer URLs: once a
  public URL is issued, changing a row to private cannot revoke that URL;
  deleting the Storage object is the revocation mechanism.
- `users:deleteMyAccount` removes the authenticated user’s profile, summaries,
  visibility rows, receipts and registered Storage objects in one bounded
  mutation. The client must separately delete local raw evidence using the
  existing local deletion path.
- The current hard-delete loop is intentionally bounded for a prototype. A
  production account with very large media history needs a scheduled,
  resumable deletion worker and an audit record before launch.
- Do not log ID tokens, raw samples, upload URLs or social media URLs. Convex
  debug logging can include sensitive request data and should remain disabled
  outside a deliberate development session.
