# Cloud, Camera Runs and Social — prototype boundary

Status: initial native prototype on `codex/cloud-camera-social-prototype`.

This phase adds optional identity and sharing without making an internet
connection a prerequisite for playing. The physical game remains local-first.

## Product contract

1. A guest can complete onboarding, play, practice, save and replay offline.
2. An account is required only to sync across devices or publish.
3. Attempt summaries may sync after sign-in. Raw motion and camera media remain
   device-only unless the player explicitly uploads them.
4. Publishing creates a separate social projection. Deleting or unpublishing
   it must not rewrite the original local attempt.
5. A failed upload stays in an idempotent outbox and never blocks another run.

## Data tiers

| Tier | Default | Examples |
| --- | --- | --- |
| Device evidence | Local only | raw IMU samples, calibration captures, unedited camera sources |
| Private sync | Opt-in through account | profile, attempt summaries, progression, equipped appearance |
| Uploaded media | Explicit per item | rendered replay MP4, edited Camera Run |
| Published social | Explicit per post | score card, caption, selected video, audience, reaction counts |

## Convex boundary

The backend lives under `services/convex/`. Every user-owned mutation derives
the owner from the verified auth identity; a client-supplied user ID is never
authorization. Client writes carry a stable operation ID so reconnect retries
are idempotent.

The iOS app keeps its existing repositories as the durable local truth and
adds an outbox/projection layer. Convex's official Swift client supplies live
queries and authenticated mutations, but it does not replace local persistence.

Authentication remains behind an app protocol. The recommended beta path is a
supported Convex Swift integration (Clerk or Auth0) configured with Sign in
with Apple. Direct Apple OIDC should not become the production choice until
token refresh, account linking and revocation have been proven on device.

References:

- <https://docs.convex.dev/client/swift/overview>
- <https://docs.convex.dev/auth/overview>
- <https://docs.convex.dev/file-storage/upload-files>

## Camera Run timeline

One monotonic timeline coordinates four independent sources:

```text
PRE-TALK ── ARM ── THROW ── CATCH ── POST-TALK
front cam ─────────────────────────────────────
rear cam  ─────────────────────────────────────
motion              ╰── evidence window ──╯
replay                         ╰── result ──╯
```

Supported devices use `AVCaptureMultiCamSession`. Unsupported or constrained
devices degrade to a selected single camera. Multi-camera is a capability, not
a requirement for a valid motion attempt.

The editor is non-destructive: it stores trims, layout, caption and replay
overlay decisions separately from source files. Export produces a new vertical
video. The original evidence and source clips stay unchanged until the player
chooses to delete them.

Apple references:

- <https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/>
- <https://developer.apple.com/documentation/avfoundation/avassetwriter>

## Social v0

The first social surface is intentionally small:

- Share Composer from a completed or historical attempt;
- audiences: Private, Friends and Public;
- Following and Discover mock feeds;
- reaction and comment counts;
- unpublish, report and block affordances;
- no public raw sensor payloads;
- no automatic upload when a run finishes.

Follower graphs, moderation operations and media access checks live on the
server. A Convex storage URL is bearer access, so private media must not rely on
the obscurity of a permanent URL.

## Prototype exit gate

- iOS builds without Convex credentials and remains fully playable offline;
- deterministic outbox/editor/timeline tests pass;
- camera permission denial and simulator/no-camera states are useful, not fatal;
- replay export produces a shareable local artifact on a physical device;
- a post cannot be published without explicit audience and upload consent;
- account deletion and social unpublish contracts are documented before a real
  deployment receives player data.
