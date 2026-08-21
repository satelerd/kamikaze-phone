import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { boundedText, requireCurrentUser } from "./lib/auth";
import { readReceipt, writeReceipt } from "./lib/idempotency";

const visibility = v.union(
  v.literal("private"),
  v.literal("friends"),
  v.literal("public"),
);

export const mine = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireCurrentUser(ctx);
    return await ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .unique();
  },
});

export const upsertMine = mutation({
  args: {
    mutationID: v.string(),
    displayName: v.string(),
    joinedAtISO8601: v.string(),
    bio: v.optional(v.string()),
    profileVisibility: visibility,
  },
  handler: async (ctx, args) => {
    const user = await requireCurrentUser(ctx);
    const operation = "profiles.upsertMine";
    const duplicate = await readReceipt(ctx, user._id, args.mutationID, operation);
    if (duplicate !== null) return duplicate;

    const existing = await ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .unique();
    const now = Date.now();
    const values = {
      displayName: boundedText(args.displayName, 64) ?? "RIDER",
      joinedAtISO8601: args.joinedAtISO8601.slice(0, 64),
      bio: boundedText(args.bio, 280),
      profileVisibility: args.profileVisibility,
      updatedAt: now,
      schemaVersion: 1,
    };
    const profileId = existing === null
      ? await ctx.db.insert("profiles", { userId: user._id, ...values })
      : existing._id;
    if (existing !== null) await ctx.db.patch("profiles", existing._id, values);
    return await writeReceipt(ctx, user._id, args.mutationID, operation, profileId);
  },
});
