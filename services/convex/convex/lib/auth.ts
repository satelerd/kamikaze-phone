import { Doc } from "../_generated/dataModel";
import { MutationCtx, QueryCtx } from "../_generated/server";

export type ReadCtx = QueryCtx | MutationCtx;

export async function getIdentity(ctx: ReadCtx) {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) {
    throw new Error("Unauthenticated");
  }
  return identity;
}

export async function findCurrentUser(ctx: ReadCtx): Promise<Doc<"users"> | null> {
  const identity = await getIdentity(ctx);
  return await ctx.db
    .query("users")
    .withIndex("by_auth_identity", (q) =>
      q.eq("authIssuer", identity.issuer).eq("authSubject", identity.subject),
    )
    .unique();
}

export async function requireCurrentUser(ctx: ReadCtx): Promise<Doc<"users">> {
  const user = await findCurrentUser(ctx);
  if (user === null) {
    throw new Error("User is not initialized; call users:ensureCurrentUser first");
  }
  return user;
}

export function boundedText(value: string | undefined, maximum: number): string | undefined {
  if (value === undefined) return undefined;
  const trimmed = value.trim();
  return trimmed.length === 0 ? undefined : trimmed.slice(0, maximum);
}

export function requireFiniteRange(value: number, minimum: number, maximum: number, name: string) {
  if (!Number.isFinite(value) || value < minimum || value > maximum) {
    throw new Error(`${name} is outside the supported range`);
  }
}
