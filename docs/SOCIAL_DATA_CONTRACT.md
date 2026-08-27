# Kamikaze social data and permissions contract

Status: local prototype contract, August 2026

This contract describes the value types under
`apps/ios/Kamikaze/Kamikaze/Features/Social/`. The shipped implementation is
offline and uses `MockSocialRepository`; it contains no Convex client, auth
flow or upload worker. The shape is intentionally ready for a future Convex
adapter without coupling the rest of Kamikaze to a network.

## Product boundary

Social shares a display-safe projection of a completed Result. Sharing never
mutates an attempt, its raw motion samples, detector interpretation, score,
profile statistics or Practice progression. A post is a separate record with
its own audience, lifecycle and moderation state.

The prototype is deliberately chronological and non-competitive:

- Following includes the viewer's followed riders and the viewer's own local
  posts that are visible to them.
- Discover includes only `public` posts from non-blocked authors.
- Reaction totals and comment counts are acknowledgements, not scores, streaks,
  rewards, rank, or an ordering signal.
- No leaderboard, follower recommendation, push notification, or popularity
  language is part of this contract.

## Convex-ready records

The Swift names are the reference shape. A future Convex schema can map the
same fields to tables without exposing local paths or raw samples in a post.

### `socialPosts`

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | opaque string | Stable post ID, independent of `attemptID`. |
| `authorID` | opaque string | Account identity; never a display name. |
| `attemptID` | opaque string | Local attempt projection source. Keep private to the owner unless the player chooses evidence sharing. |
| `trickName` | display string | Snapshot of the result label at publish time; future clients may also persist a catalog ID. |
| `caption` | string ≤ 280 | Optional player-authored text. |
| `audience` | `private \| friends \| public` | Explicit visibility. No audience inherits upload permission. |
| `state` | `published \| unpublished \| deleted` | Soft lifecycle transition for audit/recovery. |
| `publishedAt` | timestamp | Chronological feed ordering. |
| `counts` | object | Reaction and comment counts; never interpreted as a score. |
| `viewerReaction` | nullable enum | Viewer-specific projection, not shared post state. |
| `attachments` | array | References to approved media classes, not inline blobs. |

### `socialAttachments`

Each attachment has `kind`, `contentType`, a future opaque storage key,
optional byte count, and optional content hash. The local prototype uses an
opaque `localResourceID` only as a placeholder. A filesystem path, raw URL or
sensor payload must not become a public identifier.

Allowed kinds in this slice:

- `replayVideo`: a rendered replay clip. It is optional and off by default.
- `sensorEvidence`: raw motion evidence for a deliberate review context. It is
  optional, off by default, and visually marked as a sensitive attachment.

The result card itself is not an upload. It contains only the safe projection:
trick label, optional score/FIT, motion duration, outcome, capture timestamp
and an opaque local replay reference.

## Consent contract

`SocialUploadConsent` is stored with the draft/post operation:

```text
version       = social-upload-consent-v1
accepted      = true only after an affirmative control
acceptedAt    = timestamp from the affirmative consent interaction
replayVideo   = selected upload class
sensorEvidence= selected upload class
```

The current Swift model keeps the selected classes in `SocialShareDraft` and
validates the consent record against them. The upload is valid only when:

```text
no video AND no sensor evidence  → consent not required
video OR sensor evidence         → accepted + acceptedAt + current version required
```

Changing either attachment toggle clears the affirmative consent in the
composer. Selecting `public` or `friends` never silently enables video or
sensor evidence. The UI tells the player what the files can reveal before the
publish action becomes available.

The future backend should reject a request that does not include a matching
consent version and timestamp, even if a client is old or modified. Consent is
purpose-limited to the selected post and upload classes; it is not blanket
permission for future analysis or marketing.

## Mutations and privacy operations

`SocialRepository` exposes async, value-based operations:

- `fetchFeed(scope:)` and `fetchProfileSummary()` read projections only.
- `publish(_:)` creates a post after local and server-side validation.
- `unpublish(postID:)` hides the social record while retaining a recoverable
  local draft/post placeholder.
- `deletePost(postID:)` removes the social record. It never deletes the local
  attempt or raw evidence.
- `setReaction(_:on:)` replaces/removes the viewer's one reaction without
  reward side effects.
- `addComment(_:to:)` accepts 1–280 characters.
- `submitModeration(_:)` accepts report/block requests. The current UI is a
  transparent placeholder until a moderation service exists.

The future Convex adapter should enforce owner checks for unpublish/delete,
block the viewer's own deleted records from feed responses, and make
`publish` idempotent with a client-generated operation ID. The prototype keeps
that operation boundary out of SwiftUI so those rules can be added once.

## Migration notes

Do not migrate raw `NativeRunResult` or `MotionCaptureV3` into a public post.
Build a `SocialResultSnapshot` at the Result integration point. Keep the
attempt ID stable, but issue a separate post ID. If the detector re-analyzes an
attempt, a published card remains the player's published snapshot until the
player explicitly republishes it.
