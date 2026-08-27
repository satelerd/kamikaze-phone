import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const visibility = v.union(
  v.literal("private"),
  v.literal("friends"),
  v.literal("public"),
);

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

export default defineSchema({
  // One row per authenticated identity. The pair (authIssuer, authSubject)
  // is the stable external identity; Convex document IDs never leave this
  // table as a user credential.
  users: defineTable({
    authIssuer: v.string(),
    authSubject: v.string(),
    tokenIdentifier: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
    deletionRequestedAt: v.optional(v.number()),
    schemaVersion: v.number(),
  }).index("by_auth_identity", ["authIssuer", "authSubject"]),

  profiles: defineTable({
    userId: v.id("users"),
    displayName: v.string(),
    joinedAtISO8601: v.string(),
    bio: v.optional(v.string()),
    avatarMediaId: v.optional(v.id("media")),
    profileVisibility: visibility,
    updatedAt: v.number(),
    schemaVersion: v.number(),
  }).index("by_user", ["userId"]),

  // This is intentionally a projection of local AttemptSummaryV1. Raw
  // motion evidence remains on-device; only the fields needed for history,
  // stats and optional social sharing are synced here.
  attemptSummaries: defineTable({
    userId: v.id("users"),
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
    updatedAt: v.number(),
    schemaVersion: v.number(),
  })
    .index("by_user_recorded_at", ["userId", "recordedAtISO8601"])
    .index("by_user_attempt", ["userId", "attemptID"]),

  // Media is metadata plus a Convex Storage ID. Bytes are uploaded with a
  // short-lived upload URL; no raw sensor payload is placed in a mutation.
  media: defineTable({
    userId: v.id("users"),
    mediaKey: v.string(),
    attemptID: v.optional(v.string()),
    kind: v.union(v.literal("replay"), v.literal("thumbnail"), v.literal("avatar")),
    storageId: v.id("_storage"),
    contentType: v.string(),
    byteSize: v.number(),
    sha256: v.optional(v.string()),
    visibility,
    createdAt: v.number(),
    updatedAt: v.number(),
    schemaVersion: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_user_attempt", ["userId", "attemptID"])
    .index("by_user_media_key", ["userId", "mediaKey"]),

  // A separate row makes sharing an explicit, revocable decision. `friends`
  // is reserved for a future relationship table; v1 only exposes public rows
  // in the public feed and keeps private/friends rows owner-readable.
  socialVisibility: defineTable({
    userId: v.id("users"),
    attemptID: v.string(),
    visibility,
    updatedAt: v.number(),
    schemaVersion: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_user_attempt", ["userId", "attemptID"])
    .index("by_visibility", ["visibility", "updatedAt"]),

  // Every client retry reuses the same mutationID. A receipt and the entity
  // write live in the same Convex transaction, so reconnects are harmless.
  syncReceipts: defineTable({
    userId: v.id("users"),
    mutationID: v.string(),
    operation: v.string(),
    entityId: v.optional(v.string()),
    createdAt: v.number(),
    expiresAt: v.number(),
    schemaVersion: v.number(),
  })
    .index("by_user_mutation", ["userId", "mutationID"])
    .index("by_expiry", ["expiresAt"]),
});
