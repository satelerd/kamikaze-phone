import type { AuthConfig } from "convex/server";

// Convex validates the `iss` claim against this public Clerk Frontend API URL
// and the `aud` claim against the literal `convex` application ID. The value is
// configured on the Convex deployment, never read from the iOS `.env` and
// never accompanied by a Clerk secret key.
declare const process: { env: Record<string, string | undefined> };

export default {
  providers: [
    {
      domain: process.env.CLERK_JWT_ISSUER_DOMAIN!,
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
