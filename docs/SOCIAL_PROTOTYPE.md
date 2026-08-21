# Kamikaze social prototype

Status: local/mock-data SwiftUI prototype, August 2026

The Social feature is intentionally additive. It owns only
`Features/Social/**`, has no tab/root wiring, and does not edit Result, Profile,
Play, Cloud/Media, detector or Persistence. The Xcode project uses a
filesystem-synchronized group, so the new Swift files are picked up without a
project-file edit.

## Surfaces

### `SocialShareComposerView` (`ShareComposerView` alias)

Present it from Result or Beta with a display-safe `SocialResultSnapshot` and a
repository:

```swift
SocialShareComposerView(
    result: SocialResultSnapshot(...),
    repository: socialRepository
) { publishedPost in
    // Refresh the host's social summary/feed.
}
```

The composer includes a caption, private/friends/public audience picker,
optional replay-video and sensor-evidence toggles, an explicit consent control,
and a publish action disabled until the selected choices are valid. It states
that local raw evidence remains unchanged by sharing.

### `PublishedResultCardView`

Reusable result card for a feed card, Profile preview, or a future post detail.
It uses the Pitch/Ion/Hazard/Volt palette, glass-compatible surfaces, rounded
display type and monospaced evidence labels. Its decorative phone is a truthful
result thumbnail, not a second replay engine; the host can attach the existing
Result replay separately when wiring the full detail route.

### `SocialFeedView`

Following and Discover are one chronological surface selected by
`SocialFeedScopePicker`. The mock content has both friends-only and public
posts, optional replay attachments, non-gamified reaction counts and comment
previews. Every post menu includes unpublish/delete for the local author and a
report/block placeholder for other authors.

### `SocialProfileSummaryView` / `SocialProfileSummaryLoaderView`

Compact social summary for the existing Profile/Me screen. It shows following,
followers, friends and published count, then repeats the privacy rule that a
default audience does not grant upload consent. The loader uses the same
repository as the feed and remains independently embeddable.

### `SocialCommentsSheet` and `SocialModerationSheet`

Small local surfaces for the counts already shown on a post. Comments are
bounded to 280 characters. Moderation copy explicitly calls itself a
placeholder: the mock records requests and hides blocked authors locally, but
there is no claim of server-side safety or enforcement.

## Accessibility and reduced effects

- Interactive controls use at least 44-point frames and have text/icon
  accessibility labels and values.
- Audience, attachment and reaction state are exposed as values, not color
  alone; every social state includes a text label.
- `GlassSurface` owns the Reduce Transparency fallback. Social result cards
  add a high-contrast border when transparency is reduced.
- Motion in the result thumbnail is static or near-static under Reduce Motion;
  no feed meaning depends on animation.
- Empty/loading/error states are actionable and readable with Dynamic Type.
- The feed explains that reactions do not change score or progression, keeping
  the interaction legible for players who do not want gamification pressure.

## Mock repository and integration

`MockSocialRepository` is an actor conforming to `SocialRepository`. It is
deterministic, in-memory, offline and safe for previews/tests. Its async API is
the seam for a future Convex adapter; no view imports a network client.

Suggested app-shell ownership when the main integrator wires this in:

1. Construct one `SocialRepository` alongside the existing app-level stores.
2. Pass the same instance to `SocialFeedView`, the Result share composer, and
   `SocialProfileSummaryLoaderView`.
3. Map `NativeRunResult` to `SocialResultSnapshot` at the Result integration
   point. Do not pass raw samples or local file URLs to social views.
4. On publish/unpublish/delete, refresh the host's summary or feed. The local
   attempt repository remains authoritative for evidence and deletion.
5. Keep tab/root wiring outside this feature boundary.
