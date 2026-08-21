import { AuthConfig } from "convex/server";

// This development deployment intentionally starts without an identity
// provider. Convex statically resolves every environment variable referenced
// here, even behind a conditional, so optional process.env reads make a fresh
// deployment fail before the offline-first prototype can be tested.
//
// When the product chooses Clerk/Auth0 + Sign in with Apple, replace this
// empty list with that provider's checked-in public issuer/application ID
// configuration. No provider secret belongs in this file.
export default {
  providers: [],
} satisfies AuthConfig;
