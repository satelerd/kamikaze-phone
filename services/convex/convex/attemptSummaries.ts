import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { requireCurrentUser, requireFiniteRange } from "./lib/auth";
import { readReceipt, writeReceipt } from "./lib/idempotency";

const recognitionStatus = v.union(
  v.literal("recognized"),
  v.literal("review"),
  v.literal("unknown"),
  v.literal("invalid"),
);

const humanOutcome = v.union(
  v.literal("landed"),
  v.literal("missed"),
  v.literal("unclear"),
  v.literal("noAttempt"),
);

export const listMine = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const user = await requireCurrentUser(ctx);
    const requested = args.limit ?? 50;
    const limit = Math.max(1, Math.min(100, Math.floor(requested)));
    return await ctx.db
      .query("attemptSummaries")
      .withIndex("by_user_recorded_at", (q) => q.eq("userId", user._id))
      .order("desc")
      .take(limit);
  },
});

export const getMine = query({
  args: { attemptID: v.string() },
  handler: async (ctx, args) => {
    const user = await requireCurrentUser(ctx);
    return await ctx.db
      .query("attemptSummaries")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", user._id).eq("attemptID", args.attemptID),
      )
      .unique();
  },
});

export const upsert = mutation({
  args: {
    mutationID: v.string(),
    attemptID: v.string(),
    recordedAtISO8601: v.string(),
    timezoneIdentifier: v.optional(v.string()),
    trickID: v.optional(v.string()),
    recognitionStatus,
    humanOutcome: v.optional(humanOutcome),
    motionDurationMs: v.number(),
    fit: v.optional(v.number()),
    gameScore: v.optional(v.number()),
    scoreVersion: v.optional(v.string()),
    analysisVersion: v.string(),
    catalogVersion: v.string(),
    sampleCount: v.number(),
  },
  handler: async (ctx, args) => {
    const user = await requireCurrentUser(ctx);
    const operation = "attemptSummaries.upsert";
    const duplicate = await readReceipt(ctx, user._id, args.mutationID, operation);
    if (duplicate !== null) return duplicate;

    if (args.attemptID.length < 1 || args.attemptID.length > 160) {
      throw new Error("Invalid attemptID");
    }
    requireFiniteRange(args.motionDurationMs, 0, 600_000, "motionDurationMs");
    if (args.fit !== undefined) requireFiniteRange(args.fit, 0, 1, "fit");
    if (args.gameScore !== undefined) requireFiniteRange(args.gameScore, 0, 100, "gameScore");
    if (!Number.isInteger(args.sampleCount) || args.sampleCount < 0 || args.sampleCount > 2_000_000) {
      throw new Error("sampleCount is outside the supported range");
    }

    const existing = await ctx.db
      .query("attemptSummaries")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", user._id).eq("attemptID", args.attemptID),
      )
      .unique();
    // A matcher refresh must never erase a human review. A dedicated review
    // mutation can be added later if the app needs to clear one explicitly.
    const effectiveHumanOutcome = args.humanOutcome ?? existing?.humanOutcome;
    const effectiveTrickID = effectiveHumanOutcome === "noAttempt"
      ? undefined
      : args.trickID ?? existing?.trickID;
    if (
      effectiveHumanOutcome !== undefined &&
      effectiveHumanOutcome !== "noAttempt" &&
      effectiveTrickID === undefined
    ) {
      throw new Error("A reviewed attempt needs a trickID unless it is noAttempt");
    }

    const values = {
      userId: user._id,
      attemptID: args.attemptID,
      recordedAtISO8601: args.recordedAtISO8601.slice(0, 64),
      timezoneIdentifier: args.timezoneIdentifier?.slice(0, 64),
      trickID: effectiveTrickID?.slice(0, 120),
      recognitionStatus: args.recognitionStatus,
      humanOutcome: effectiveHumanOutcome,
      motionDurationMs: args.motionDurationMs,
      fit: args.fit,
      gameScore: args.gameScore,
      scoreVersion: args.scoreVersion?.slice(0, 64),
      analysisVersion: args.analysisVersion.slice(0, 120),
      catalogVersion: args.catalogVersion.slice(0, 120),
      sampleCount: args.sampleCount,
      updatedAt: Date.now(),
      schemaVersion: 1,
    };
    if (existing === null) {
      const id = await ctx.db.insert("attemptSummaries", values);
      return await writeReceipt(ctx, user._id, args.mutationID, operation, id);
    }
    await ctx.db.patch("attemptSummaries", existing._id, values);
    return await writeReceipt(ctx, user._id, args.mutationID, operation, existing._id);
  },
});

export const deleteMine = mutation({
  args: { mutationID: v.string(), attemptID: v.string() },
  handler: async (ctx, args) => {
    const user = await requireCurrentUser(ctx);
    const operation = "attemptSummaries.deleteMine";
    const duplicate = await readReceipt(ctx, user._id, args.mutationID, operation);
    if (duplicate !== null) return duplicate;

    const attempt = await ctx.db
      .query("attemptSummaries")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", user._id).eq("attemptID", args.attemptID),
      )
      .unique();
    if (attempt !== null) await ctx.db.delete("attemptSummaries", attempt._id);

    const media = await ctx.db
      .query("media")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", user._id).eq("attemptID", args.attemptID),
      )
      .collect();
    for (const item of media) {
      await ctx.storage.delete(item.storageId);
      await ctx.db.delete("media", item._id);
    }

    const visibility = await ctx.db
      .query("socialVisibility")
      .withIndex("by_user_attempt", (q) =>
        q.eq("userId", user._id).eq("attemptID", args.attemptID),
      )
      .unique();
    if (visibility !== null) await ctx.db.delete("socialVisibility", visibility._id);

    return await writeReceipt(
      ctx,
      user._id,
      args.mutationID,
      operation,
      attempt?._id,
    );
  },
});
