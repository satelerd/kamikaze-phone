# Account / Clerk surface

`Features/Account` is the optional identity surface used by Me/Profile and the
Beta account entry. It keeps guest play local and exposes a display-safe `AccountIdentity` projection
instead of passing Clerk's full `User` model into social or result screens.

## Current UI states

- Loading: a quiet state card while Clerk's environment/client resolves.
- Signed out: Sign in with Apple is the primary action; `SIGN IN` and `SIGN
  UP` are separate, explicit routes. A missing publishable key disables those
  actions and explains how to configure the app.
- Signed in: avatar, name, email, verification state, Clerk identity tag,
  private-sync placeholder, manage-account sheet, sign out, and a disabled
  `DELETE ACCOUNT · FUTURE` row.

The surface does not upload camera, motion, replay or sensor data. Account
existence is not consent to share those payloads; the Social share composer
still records audience and explicit upload consent per draft.

## Integration API

The app composition root owns `Clerk.configure(...)` and injects the configured
instance. The Profile/Me and Beta routes mount:

```swift
ClerkAccountSurface(clerk: KamikazeIdentityConfiguration.clerk)
```

`ClerkAccountSurface` is conditionally compiled only when `ClerkKit` and
`ClerkKitUI` are available. Passing `nil` renders the local, config-needed
state without touching `Clerk.shared` (which would assert before configuration).

When configured, the bridge uses the official Clerk iOS 1.4 APIs:

- `clerk.user` and `clerk.isLoaded` for loading/signed-out/signed-in state.
- `try await clerk.auth.signInWithApple()` for the primary Apple action.
- `AuthView(mode: .signInOrUp/.signIn/.signUp)` for email/identifier flows.
- `UserProfileView(isDismissible: true)` for profile/security/account controls.
- `try await clerk.auth.signOut()` for the explicit sign-out row.
- `.prefetchClerkImages()` for the avatar/profile image path.

The root must provide a real `KamikazeClerkPublishableKey` (publishable keys
only; never a Clerk secret key). Sign in with Apple also requires the Apple
capability and provider setup in the Clerk Dashboard. The current bridge asks
for `.email` and `.fullName` through Clerk's native Apple helper, while the
adapter derives the display name from `User.firstName`/`lastName` and the email
from `User.primaryEmailAddress`.

## Test / preview seam

`AccountSession` is the local seam. `UnconfiguredAccountSession` never creates
an identity, while `MockAccountSession` is deterministic for previews and
tests:

```swift
AccountView(
    session: MockAccountSession(snapshot: .previewSignedIn),
    isConfigured: true
)
```

No upload is hidden in this feature. The authenticated Convex transport lives
in `Cloud/ClerkConvexTransport.swift`; composing it with the outbox remains an
explicit app-level action so signing in alone never uploads motion or camera
data. Account deletion remains unavailable until retention/cascade policy is
approved.
