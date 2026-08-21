/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";
import type * as attemptSummaries from "../attemptSummaries.js";
import type * as lib_auth from "../lib/auth.js";
import type * as lib_idempotency from "../lib/idempotency.js";
import type * as media from "../media.js";
import type * as profiles from "../profiles.js";
import type * as social from "../social.js";
import type * as users from "../users.js";

/**
 * A utility for referencing Convex functions in your app's API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
declare const fullApi: ApiFromModules<{
  attemptSummaries: typeof attemptSummaries;
  "lib/auth": typeof lib_auth;
  "lib/idempotency": typeof lib_idempotency;
  media: typeof media;
  profiles: typeof profiles;
  social: typeof social;
  users: typeof users;
}>;
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;
