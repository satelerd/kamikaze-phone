// Coordination scoring for Co-op Sync: how simultaneous, how matched, how stylish.
// Shared by the two-phone linked mode, the single-phone pass mode, and the
// desktop simulation, so every path scores exactly the same way.
import { FXEngine } from '@/lib/fx';
import { speak } from '@/lib/speech';
import { unlockAchievement } from '@/lib/store';
import { ThrowTracker, classifyThrow } from '@/lib/physics';
import type { ThrowRecord } from '@/lib/physics';
import type { CoopGrade, ThrowMessage } from '@/lib/peer';
import type { IMUSample, TrickResult } from '@/lib/types';

export const COUNTDOWN_LEAD_MS = 3600;
export const SYNC_ACHIEVEMENT_ID = 'sync-souls';
const BEST_KEY = 'kamikaze-coop-best-sync-v1';

/** One rider's throw, normalized to the LOCAL clock (epoch ms). */
export interface RiderThrow {
  name: string;
  launchEpoch: number;
  landEpoch: number;
  /** seconds of freefall */
  airtime: number;
  trickId: string;
  trickName: string;
  score: number;
  grade: CoopGrade;
}

/** linked = two phones at once; pass = alternating throws on one phone. */
export type SyncMode = 'linked' | 'pass';

export type SyncGrade = 'SOUL MATES' | 'IN SYNC' | 'KINDA' | 'CHAOS';

export interface SyncBreakdown {
  mode: SyncMode;
  /** |Δlaunch| after offset correction; null in pass mode (throws are sequential) */
  launchDeltaMs: number | null;
  /** relative airtime difference, 0..1 */
  airtimeDeltaPct: number;
  /** 0..100, null in pass mode */
  simultaneity: number | null;
  /** 0..100 */
  airtimeMatch: number;
  /** avg of both trick scores, 0..100 */
  styleAvg: number;
  trickMatch: boolean;
  /** final 0..100 */
  sync: number;
  grade: SyncGrade;
}

function clamp(n: number, lo = 0, hi = 100): number {
  return Math.max(lo, Math.min(hi, n));
}

/**
 * Coordination Score:
 * - launch simultaneity: 100% at |Δlaunch| < 50ms, 0% at > 800ms (linked only)
 * - airtime match: 100% at < 5% relative difference, 0% at > 40%
 * - combined style: average of both trick scores, weighted 30%
 * - trick match bonus: same trickId adds +15
 */
export function computeSync(a: RiderThrow, b: RiderThrow, mode: SyncMode): SyncBreakdown {
  const launchDeltaMs = mode === 'linked' ? Math.abs(a.launchEpoch - b.launchEpoch) : null;
  const simultaneity =
    launchDeltaMs === null
      ? null
      : launchDeltaMs <= 50
        ? 100
        : launchDeltaMs >= 800
          ? 0
          : ((800 - launchDeltaMs) / 750) * 100;

  const longest = Math.max(a.airtime, b.airtime, 0.01);
  const airtimeDeltaPct = Math.abs(a.airtime - b.airtime) / longest;
  const airtimeMatch =
    airtimeDeltaPct <= 0.05
      ? 100
      : airtimeDeltaPct >= 0.4
        ? 0
        : ((0.4 - airtimeDeltaPct) / 0.35) * 100;

  const styleAvg = (a.score + b.score) / 2;
  const trickMatch = a.trickId === b.trickId;
  const bonus = trickMatch ? 15 : 0;

  const raw =
    mode === 'linked'
      ? (simultaneity ?? 0) * 0.4 + airtimeMatch * 0.3 + styleAvg * 0.3 + bonus
      : airtimeMatch * 0.55 + styleAvg * 0.3 + bonus;

  const sync = Math.round(clamp(raw));
  const grade: SyncGrade =
    sync >= 90 ? 'SOUL MATES' : sync >= 70 ? 'IN SYNC' : sync >= 40 ? 'KINDA' : 'CHAOS';

  return {
    mode,
    launchDeltaMs,
    airtimeDeltaPct,
    simultaneity: simultaneity === null ? null : Math.round(simultaneity),
    airtimeMatch: Math.round(airtimeMatch),
    styleAvg: Math.round(styleAvg),
    trickMatch,
    sync,
    grade,
  };
}

export function calloutFor(bd: SyncBreakdown): string {
  switch (bd.grade) {
    case 'SOUL MATES':
      return `Soul mates! ${bd.sync} percent sync. Two phones, one heartbeat!`;
    case 'IN SYNC':
      return `In sync, riders! ${bd.sync} percent. The stoke is mutual!`;
    case 'KINDA':
      return `Kinda vibing at ${bd.sync} percent. Tighten up that drop, dudes.`;
    case 'CHAOS':
      return `Total chaos! ${bd.sync} percent. Same planet, different universes, brah.`;
  }
}

// ---------------------------------------------------------------------------
// Time anchoring: ThrowRecord timestamps are sensor-session relative.
// The onThrow callback fires as the sample at t = landT + settleMs is fed,
// so Date.now() at that moment anchors the whole record to the wall clock.
// ---------------------------------------------------------------------------
export function launchEpochOf(rec: ThrowRecord): number {
  return Date.now() - (rec.landT + rec.settleMs - rec.launchT);
}

export function landEpochOf(rec: ThrowRecord): number {
  return Date.now() - rec.settleMs;
}

// ---------------------------------------------------------------------------
// Adapters between TrickResult, the wire format, and RiderThrow
// ---------------------------------------------------------------------------
export function riderFromResult(
  result: TrickResult,
  launchEpoch: number,
  landEpoch: number,
  name: string,
): RiderThrow {
  return {
    name,
    launchEpoch,
    landEpoch,
    airtime: result.features.airtime,
    trickId: result.trickId,
    trickName: result.trickName,
    score: result.score,
    grade: result.grade,
  };
}

export function throwMessageOf(rider: RiderThrow): ThrowMessage {
  return {
    t: 'throw',
    launchT: rider.launchEpoch,
    landT: rider.landEpoch,
    airtime: rider.airtime,
    trickId: rider.trickId,
    trickName: rider.trickName,
    score: rider.score,
    grade: rider.grade,
  };
}

/** Parse a partner's throw message, converting their clock into ours. */
export function riderFromThrowMessage(
  m: ThrowMessage,
  toLocal: (remoteEpochMs: number) => number,
  name: string,
): RiderThrow {
  return {
    name,
    launchEpoch: toLocal(m.launchT),
    landEpoch: toLocal(m.landT),
    airtime: m.airtime,
    trickId: m.trickId,
    trickName: m.trickName,
    score: m.score,
    grade: m.grade,
  };
}

/** Run a synthetic sample stream through a standalone tracker + classifier. */
export function classifySamples(samples: IMUSample[], mode = 'coop'): TrickResult | null {
  const results: TrickResult[] = [];
  const tracker = new ThrowTracker((rec) => results.push(classifyThrow(rec, mode)));
  for (const s of samples) tracker.feed(s);
  return results[0] ?? null;
}

// ---------------------------------------------------------------------------
// Best sync persistence + celebration
// ---------------------------------------------------------------------------
export function loadBestSync(): number {
  if (typeof window === 'undefined') return 0;
  try {
    const raw = window.localStorage.getItem(BEST_KEY);
    const n = raw ? Number(raw) : 0;
    return Number.isFinite(n) ? n : 0;
  } catch {
    return 0;
  }
}

function saveBestSync(sync: number): { best: number; isNewBest: boolean } {
  const prev = loadBestSync();
  if (sync <= prev) return { best: prev, isNewBest: false };
  try {
    window.localStorage.setItem(BEST_KEY, String(sync));
  } catch {
    // private mode or full storage: the session still counts
  }
  return { best: sync, isNewBest: true };
}

/** Speak the result, persist the best, maybe unlock the achievement. */
export function celebrateSync(bd: SyncBreakdown): { best: number; isNewBest: boolean } {
  speak(calloutFor(bd), { style: 'surfer', interrupt: true });
  const saved = saveBestSync(bd.sync);
  try {
    if (bd.sync >= 90 && unlockAchievement(SYNC_ACHIEVEMENT_ID)) {
      FXEngine.handle({ type: 'achievement', id: SYNC_ACHIEVEMENT_ID });
    }
  } catch {
    // achievements must never crash the party
  }
  return saved;
}
