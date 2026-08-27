import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { boundedText, getIdentity, requireCurrentUser } from "./lib/auth";

export const ensureCurrentUser = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await getIdentity(ctx);
    const now = Date.now();
    const existing = await ctx.db
      .query("users")
      .withIndex("by_auth_identity", (q) =>
        q.eq("authIssuer", identity.issuer).eq("authSubject", identity.subject),
      )
      .unique();

    if (existing !== null) {
      await ctx.db.patch("users", existing._id, {
        tokenIdentifier: identity.tokenIdentifier,
        updatedAt: now,
      });
      const profile = await ctx.db
        .query("profiles")
        .withIndex("by_user", (q) => q.eq("userId", existing._id))
        .unique();
      return {
        userId: existing._id,
        profileId: profile?._id ?? null,
        created: false,
      };
    }

    const userId = await ctx.db.insert("users", {
      authIssuer: identity.issuer,
      authSubject: identity.subject,
      tokenIdentifier: identity.tokenIdentifier,
      createdAt: now,
      updatedAt: now,
      schemaVersion: 1,
    });
    const profileId = await ctx.db.insert("profiles", {
      userId,
      displayName: boundedText(identity.name, 64) ?? "RIDER",
      joinedAtISO8601: new Date(now).toISOString(),
      profileVisibility: "private",
      updatedAt: now,
      schemaVersion: 1,
    });
    return { userId, profileId, created: true };
  },
});

export const me = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireCurrentUser(ctx);
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .unique();
    return {
      userId: user._id,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      profile: profile === null
        ? null
        : {
            profileId: profile._id,
            displayName: profile.displayName,
            joinedAtISO8601: profile.joinedAtISO8601,
            bio: profile.bio ?? null,
            profileVisibility: profile.profileVisibility,
            updatedAt: profile.updatedAt,
          },
    };
  },
});

// This is intentionally a hard-delete prototype. It removes database rows
// and Convex Storage objects owned by the authenticated user in one mutation.
// A production account with very large media history should move this loop to
// a bounded scheduled worker before increasing the dataset limits.
export const deleteMyAccount = mutation({
  args: { mutationID: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const identity = await getIdentity(ctx);
    if (args.mutationID !== undefined && args.mutationID.length > 160) {
      throw new Error("Invalid mutationID");
    }
    const user = await ctx.db
      .query("users")
      .withIndex("by_auth_identity", (q) =>
        q.eq("authIssuer", identity.issuer).eq("authSubject", identity.subject),
      )
      .unique();
    // Repeating deletion after a successful request is safe and does not
    // disclose whether another identity owns any matching records.
    if (user === null) return { deleted: true, alreadyDeleted: true };

    const media = await ctx.db
      .query("media")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    for (const item of media) {
      await ctx.storage.delete(item.storageId);
      await ctx.db.delete("media", item._id);
    }

    const attempts = await ctx.db
      .query("attemptSummaries")
      .withIndex("by_user_recorded_at", (q) => q.eq("userId", user._id))
      .collect();
    for (const attempt of attempts) await ctx.db.delete("attemptSummaries", attempt._id);

    const visibilityRows = await ctx.db
      .query("socialVisibility")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    for (const row of visibilityRows) await ctx.db.delete("socialVisibility", row._id);

    const profiles = await ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    for (const profile of profiles) await ctx.db.delete("profiles", profile._id);

    const receipts = await ctx.db
      .query("syncReceipts")
      .withIndex("by_user_mutation", (q) => q.eq("userId", user._id))
      .collect();
    for (const receipt of receipts) await ctx.db.delete("syncReceipts", receipt._id);

    await ctx.db.delete("users", user._id);
    return { deleted: true, alreadyDeleted: false };
  },
});
