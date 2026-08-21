import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { requireCurrentUser, requireFiniteRange } from "./lib/auth";
import { readReceipt, writeReceipt } from "./lib/idempotency";

const visibility = v.union(
  v.literal("private"),
  v.literal("friends"),
  v.literal("public"),
);

const mediaKind = v.union(
  v.literal("replay"),
  v.literal("thumbnail"),
  v.literal("avatar"),
);

export const generateUploadURL = mutation({
  args: {},
  handler: async (ctx) => {
    await requireCurrentUser(ctx);
    return await ctx.storage.generateUploadUrl();
  },
});

export const mine = query({
  args: {},
  handler: async (ctx) => {
    const user = await requireCurrentUser(ctx);
    const rows = await ctx.db
      .query("media")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    return await Promise.all(rows.map(async (row) => ({
      ...row,
      downloadUrl: await ctx.storage.getUrl(row.storageId),
    })));
  },
});

export const register = mutation({
  args: {
    mutationID: v.string(),
    mediaKey: v.string(),
    attemptID: v.optional(v.string()),
    kind: mediaKind,
    storageId: v.id("_storage"),
    contentType: v.string(),
    byteSize: v.number(),
    sha256: v.optional(v.string()),
    visibility,
  },
  handler: async (ctx, args) => {
    const user = await requireCurrentUser(ctx);
    const operation = "media.register";
    const duplicate = await readReceipt(ctx, user._id, args.mutationID, operation);
    if (duplicate !== null) return duplicate;
    if (!/^[A-Za-z0-9._:-]{1,160}$/.test(args.mediaKey)) throw new Error("Invalid mediaKey");
    requireFiniteRange(args.byteSize, 0, 100 * 1024 * 1024, "byteSize");
    if (args.attemptID !== undefined) {
      const attempt = await ctx.db
        .query("attemptSummaries")
        .withIndex("by_user_attempt", (q) =>
          q.eq("userId", user._id).eq("attemptID", args.attemptID!),
        )
        .unique();
      if (attempt === null) throw new Error("Attempt does not belong to the current user");
    }

    const existing = await ctx.db
      .query("media")
      .withIndex("by_user_media_key", (q) =>
        q.eq("userId", user._id).eq("mediaKey", args.mediaKey),
      )
      .unique();
    if (existing !== null && existing.storageId !== args.storageId) {
      await ctx.storage.delete(existing.storageId);
    }
    const values = {
      userId: user._id,
      mediaKey: args.mediaKey,
      attemptID: args.attemptID,
      kind: args.kind,
      storageId: args.storageId,
      contentType: args.contentType.slice(0, 120),
      byteSize: args.byteSize,
      sha256: args.sha256?.slice(0, 128),
      visibility: args.visibility,
      createdAt: existing?.createdAt ?? Date.now(),
      updatedAt: Date.now(),
      schemaVersion: 1,
    };
    const mediaId = existing === null
      ? await ctx.db.insert("media", values)
      : existing._id;
    if (existing !== null) await ctx.db.patch("media", existing._id, values);
    return await writeReceipt(ctx, user._id, args.mutationID, operation, mediaId);
  },
});

export const deleteMine = mutation({
  args: { mutationID: v.string(), mediaKey: v.string() },
  handler: async (ctx, args) => {
    const user = await requireCurrentUser(ctx);
    const operation = "media.deleteMine";
    const duplicate = await readReceipt(ctx, user._id, args.mutationID, operation);
    if (duplicate !== null) return duplicate;
    const media = await ctx.db
      .query("media")
      .withIndex("by_user_media_key", (q) =>
        q.eq("userId", user._id).eq("mediaKey", args.mediaKey),
      )
      .unique();
    if (media !== null) {
      await ctx.storage.delete(media.storageId);
      await ctx.db.delete("media", media._id);
    }
    return await writeReceipt(ctx, user._id, args.mutationID, operation, media?._id);
  },
});
