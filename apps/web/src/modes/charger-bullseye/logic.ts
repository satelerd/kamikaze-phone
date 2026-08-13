// Charger Bullseye logic: Battery Status API types (not in lib.dom) plus the
// judge that matches a detected landing with a charging=true flip within 3s.
export interface BatteryLike extends EventTarget {
  charging: boolean;
  level: number;
}

/** navigator.getBattery() is Chromium-only and missing from lib.dom. */
export function getBattery(): Promise<BatteryLike> | null {
  if (typeof navigator === 'undefined') return null;
  const nav = navigator as Navigator & { getBattery?: () => Promise<BatteryLike> };
  return nav.getBattery ? nav.getBattery() : null;
}

export const BULLSEYE_CFG = {
  /** charging must flip on within this window after landing */
  windowMs: 3000,
  /** allow a flip slightly before the settle-confirmed landing timestamp */
  preRollMs: 600,
};

export interface BullseyeVerdict {
  hit: boolean;
  /** ms from landing to charging flip (0 for pre-roll hits) */
  latencyMs: number;
}

/**
 * Matches landings (wall-clock ms, performance.now timeline) against
 * chargingchange events. One pending landing at a time.
 */
export class BullseyeJudge {
  private charging = false;
  private lastChargeOnAt = -Infinity;
  private pending: {
    landAt: number;
    cb: (v: BullseyeVerdict) => void;
    timer: ReturnType<typeof setTimeout>;
  } | null = null;

  /** Set the initial charging state without treating it as a fresh flip. */
  prime(charging: boolean): void {
    this.charging = charging;
  }

  isCharging(): boolean {
    return this.charging;
  }

  noteCharging(charging: boolean, at: number = performance.now()): void {
    const was = this.charging;
    this.charging = charging;
    if (charging && !was) {
      this.lastChargeOnAt = at;
      if (this.pending && at >= this.pending.landAt - BULLSEYE_CFG.preRollMs) {
        this.settle(true, Math.max(0, at - this.pending.landAt));
      }
    }
  }

  noteLanding(landAt: number, cb: (v: BullseyeVerdict) => void): void {
    this.cancel();
    // The pad may have flipped charging on during the settle window already.
    if (this.charging && this.lastChargeOnAt >= landAt - BULLSEYE_CFG.preRollMs) {
      cb({ hit: true, latencyMs: Math.max(0, Math.round(this.lastChargeOnAt - landAt)) });
      return;
    }
    const remaining = Math.max(0, landAt + BULLSEYE_CFG.windowMs - performance.now());
    const timer = setTimeout(() => this.settle(false, BULLSEYE_CFG.windowMs), remaining);
    this.pending = { landAt, cb, timer };
  }

  cancel(): void {
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending = null;
    }
  }

  private settle(hit: boolean, latencyMs: number): void {
    if (!this.pending) return;
    const { cb, timer } = this.pending;
    clearTimeout(timer);
    this.pending = null;
    cb({ hit, latencyMs: Math.round(latencyMs) });
  }
}
