// Fridge Surfer detection: throw + land the phone on a magnetic surface.
// A ThrowTracker (IMU) detects the landing; this detector watches the
// magnetometer for a post-landing magnitude spike vs a calibrated baseline.
import type { MagSample } from '@/lib/types';

export type SurfCalPhase = 'idle' | 'calibrating' | 'ready';

export interface MagVerdict {
  magnetic: boolean;
  /** peak |mag - baseline| µT within the verdict window after landing */
  peakDelta: number;
  samples: number;
}

export const SURF_CFG = {
  calibrateMs: 2500,
  /** µT deviation that counts as a magnetic landing */
  magneticDelta: 35,
  /** how long after landT we look for the spike */
  verdictWindowMs: 1000,
  /** wall-clock safety timeout if mag samples stop arriving */
  verdictTimeoutMs: 2200,
};

export interface SurfHooks {
  onPhase?: (phase: SurfCalPhase) => void;
  onCalibrated?: (baseline: number) => void;
  onLive?: (mag: number, delta: number) => void;
}

export class MagLandingDetector {
  phase: SurfCalPhase = 'idle';
  baseline = 0;
  private hooks: SurfHooks;
  private calStart = -1;
  private calSamples: number[] = [];
  private buffer: MagSample[] = [];
  private pending: {
    landT: number;
    cb: (v: MagVerdict) => void;
    timer: ReturnType<typeof setTimeout>;
  } | null = null;

  constructor(hooks: SurfHooks = {}) {
    this.hooks = hooks;
  }

  beginCalibration(): void {
    this.phase = 'calibrating';
    this.calStart = -1;
    this.calSamples = [];
    this.hooks.onPhase?.('calibrating');
  }

  feedMag(s: MagSample): void {
    this.buffer.push(s);
    while (this.buffer.length && this.buffer[0].t < s.t - 8000) this.buffer.shift();

    if (this.phase === 'calibrating') {
      if (this.calStart < 0) this.calStart = s.t;
      this.calSamples.push(s.mag);
      this.hooks.onLive?.(s.mag, 0);
      if (s.t - this.calStart >= SURF_CFG.calibrateMs && this.calSamples.length >= 5) {
        const sorted = [...this.calSamples].sort((a, b) => a - b);
        this.baseline = sorted[Math.floor(sorted.length / 2)];
        this.phase = 'ready';
        this.hooks.onCalibrated?.(this.baseline);
        this.hooks.onPhase?.('ready');
      }
      return;
    }

    this.hooks.onLive?.(s.mag, Math.abs(s.mag - this.baseline));
    if (this.pending && s.t >= this.pending.landT + SURF_CFG.verdictWindowMs) this.resolve();
  }

  /** Ask for the magnetic verdict on a landing at landT (sensor timeline). */
  judgeLanding(landT: number, cb: (v: MagVerdict) => void): void {
    this.cancelPending();
    const timer = setTimeout(() => this.resolve(), SURF_CFG.verdictTimeoutMs);
    this.pending = { landT, cb, timer };
    const last = this.buffer[this.buffer.length - 1];
    if (last && last.t >= landT + SURF_CFG.verdictWindowMs) this.resolve();
  }

  cancelPending(): void {
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending = null;
    }
  }

  private resolve(): void {
    if (!this.pending) return;
    const { landT, cb, timer } = this.pending;
    clearTimeout(timer);
    this.pending = null;
    const win = this.buffer.filter(
      (m) => m.t >= landT && m.t <= landT + SURF_CFG.verdictWindowMs,
    );
    const peakDelta = win.reduce((acc, m) => Math.max(acc, Math.abs(m.mag - this.baseline)), 0);
    cb({
      magnetic: win.length > 0 && peakDelta >= SURF_CFG.magneticDelta,
      peakDelta,
      samples: win.length,
    });
  }
}
