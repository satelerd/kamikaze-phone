import { Doc, Id } from "../_generated/dataModel";
import { MutationCtx } from "../_generated/server";

export const RECEIPT_TTL_MS = 1000 * 60 * 60 * 24 * 30;

export type MutationAck = {
  ok: true;
  operation: string;
  entityId: string | null;
  deduplicated: boolean;
};

function validateMutationID(mutationID: string) {
  if (!/^[A-Za-z0-9._:-]{1,160}$/.test(mutationID)) {
    throw new Error("Invalid mutationID");
  }
}

export async function readReceipt(
  ctx: MutationCtx,
  userId: Id<"users">,
  mutationID: string,
  operation: string,
): Promise<MutationAck | null> {
  validateMutationID(mutationID);
  const receipt = await ctx.db
    .query("syncReceipts")
    .withIndex("by_user_mutation", (q) =>
      q.eq("userId", userId).eq("mutationID", mutationID),
    )
    .unique();
  if (receipt === null) return null;
  if (receipt.operation !== operation) {
    throw new Error("Mutation ID was already used for another operation");
  }
  return ackFromReceipt(receipt);
}

export async function writeReceipt(
  ctx: MutationCtx,
  userId: Id<"users">,
  mutationID: string,
  operation: string,
  entityId?: string,
): Promise<MutationAck> {
  validateMutationID(mutationID);
  await ctx.db.insert("syncReceipts", {
    userId,
    mutationID,
    operation,
    entityId,
    createdAt: Date.now(),
    expiresAt: Date.now() + RECEIPT_TTL_MS,
    schemaVersion: 1,
  });
  return {
    ok: true,
    operation,
    entityId: entityId ?? null,
    deduplicated: false,
  };
}

function ackFromReceipt(receipt: Doc<"syncReceipts">): MutationAck {
  return {
    ok: true,
    operation: receipt.operation,
    entityId: receipt.entityId ?? null,
    deduplicated: true,
  };
}
