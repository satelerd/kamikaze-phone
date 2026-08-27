import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { mutation, query, QueryCtx } from "./_generated/server";
import { requireCurrentUser } from "./lib/auth";
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
      .query("socialVisibility")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
  },
});

export const setVisibility = mutation({
  args: {
    mutationID: v.string(),
    attemptID: v.string(),
    visibility,
  },
  handler: async (ctx, args) => {
    const user = await requireCurrentUser(ctx);
    const operation = "social.setVisibility";
    const duplicate = await readReceipt(ctx, user._id, args.mutationID, operation);
    if (duplicate !== null) return duplicate;
    const attempt = await ctx.db
      .query("attemptSummaries")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", user._id).eq("attemptID", args.attemptID),
      )
      .unique();
    if (attempt === null) throw new Error("Attempt does not belong to the current user");

    const existing = await ctx.db
      .query("socialVisibility")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", user._id).eq("attemptID", args.attemptID),
      )
      .unique();
    const values = {
      userId: user._id,
      attemptID: args.attemptID,
      visibility: args.visibility,
      updatedAt: Date.now(),
      schemaVersion: 1,
    };
    const visibilityId = existing === null
      ? await ctx.db.insert("socialVisibility", values)
      : existing._id;
    if (existing !== null) await ctx.db.patch("socialVisibility", existing._id, values);
    return await writeReceipt(ctx, user._id, args.mutationID, operation, visibilityId);
  },
});

export const publicAttempt = query({
  args: { userId: v.id("users"), attemptID: v.string() },
  handler: async (ctx, args) => {
    const row = await ctx.db
      .query("socialVisibility")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", args.userId).eq("attemptID", args.attemptID),
      )
      .unique();
    if (row === null || row.visibility !== "public") return null;
    const attempt = await ctx.db
      .query("attemptSummaries")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", args.userId).eq("attemptID", args.attemptID),
      )
      .unique();
    if (attempt === null) return null;
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .unique();
    const media = await publicMedia(ctx, args.userId, args.attemptID);
    return {
      userId: args.userId,
      profile: profile === null || profile.profileVisibility !== "public"
        ? null
        : { displayName: profile.displayName },
      attempt,
      media,
    };
  },
});

export const publicFeed = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const requested = args.limit ?? 30;
    const limit = Math.max(1, Math.min(100, Math.floor(requested)));
    const rows = await ctx.db
      .query("socialVisibility")
      .withIndex("by_visibility", (q) => q.eq("visibility", "public"))
      .order("desc")
      .take(limit);
    const result = [];
    for (const row of rows) {
      const attempt = await ctx.db
        .query("attemptSummaries")
        .withIndex("by_user_attempt", (q) =>
          q.eq("userId", row.userId).eq("attemptID", row.attemptID),
        )
        .unique();
      if (attempt === null) continue;
      const profile = await ctx.db
        .query("profiles")
        .withIndex("by_user", (q) => q.eq("userId", row.userId))
        .unique();
      result.push({
        userId: row.userId,
        profile: profile === null || profile.profileVisibility !== "public"
          ? null
          : { displayName: profile.displayName },
        attempt,
        media: await publicMedia(ctx, row.userId, row.attemptID),
      });
    }
    return result;
  },
});

async function publicMedia(ctx: QueryCtx, userId: Id<"users">, attemptID: string) {
  const rows = await ctx.db
    .query("media")
    .withIndex("by_user_attempt", (q) =>
      q.eq("userId", userId).eq("attemptID", attemptID),
    )
    .collect();
  const visible = rows.filter((row) => row.visibility === "public");
  return await Promise.all(visible.map(async (row) => ({
    mediaKey: row.mediaKey,
    kind: row.kind,
    contentType: row.contentType,
    byteSize: row.byteSize,
    downloadUrl: await ctx.storage.getUrl(row.storageId),
  })));
}
