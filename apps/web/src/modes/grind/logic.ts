// Rail Grind detection: sustained magnetometer deviation from a calibrated
// baseline while the IMU shows sliding motion. Pure logic; the page feeds it
// samples from SensorEngine (live) or the simulator.
import type { IMUSample, MagSample } from '@/lib/types';

export type GrindPhase = 'idle' | 'calibrating' | 'ready' | 'grinding';

export interface GrindResult {
  durationMs: number;
  /** 0..1, low delta variance = buttery grind */
  steadiness: number;
  /** mean µT deviation while on the rail */
  avgDelta: number;
  peakDelta: number;
  points: number;
}

export interface GrindEvents {
  onPhase?: (phase: GrindPhase) => void;
  onCalibrated?: (baseline: number) => void;
  onStart?: () => void;
  onTick?: (intensity: number, delta: number) => void;
  /** result is null when the contact was too short to count */
  onEnd?: (result: GrindResult | null, durationMs: number) => void;
  onLive?: (mag: number, delta: number) => void;
}

export const GRIND_CFG = {
  calibrateMs: 3000,
  /** µT above baseline = touching steel */
  contactDelta: 22,
  /** hysteresis: below this the rail is gone */
  releaseDelta: 12,
  /** m/s² linear-accel RMS that counts as sliding */
  minMotion: 0.3,
  /** ms of lost contact before the grind ends */
  graceMs: 200,
  minGrindMs: 250,
  /** µT delta that maps to FX intensity 1.0 */
  intensitySpan: 130,
};

export class GrindTracker {
  phase: GrindPhase = 'idle';
  baseline = 0;
  private ev: GrindEvents;
  private calStart = -1;
  private calSamples: number[] = [];
  private motion: { t: number; a: number }[] = [];
  private grindStart = 0;
  private lastContact = 0;
  private deltas: number[] = [];

  constructor(ev: GrindEvents) {
    this.ev = ev;
  }

  /** Hold the phone away from metal; baseline locks after ~3s of readings. */
  beginCalibration(): void {
    this.phase = 'calibrating';
    this.calStart = -1;
    this.calSamples = [];
    this.ev.onPhase?.('calibrating');
  }

  feedIMU(s: IMUSample): void {
    const a = Math.hypot(s.lx, s.ly, s.lz);
    this.motion.push({ t: s.t, a });
    while (this.motion.length && this.motion[0].t < s.t - 400) this.motion.shift();
  }

  private motionRms(now: number): number {
    const recent = this.motion.filter((m) => m.t >= now - 300);
    if (!recent.length) return 0;
    return Math.sqrt(recent.reduce((acc, m) => acc + m.a * m.a, 0) / recent.length);
  }

  feedMag(s: MagSample): void {
    const delta = Math.abs(s.mag - this.baseline);
    switch (this.phase) {
      case 'idle':
        this.ev.onLive?.(s.mag, 0);
        break;
      case 'calibrating': {
        if (this.calStart < 0) this.calStart = s.t;
        this.calSamples.push(s.mag);
        this.ev.onLive?.(s.mag, 0);
        if (s.t - this.calStart >= GRIND_CFG.calibrateMs && this.calSamples.length >= 5) {
          const sorted = [...this.calSamples].sort((a, b) => a - b);
          this.baseline = sorted[Math.floor(sorted.length / 2)];
          this.phase = 'ready';
          this.ev.onCalibrated?.(this.baseline);
          this.ev.onPhase?.('ready');
        }
        break;
      }
      case 'ready': {
        this.ev.onLive?.(s.mag, delta);
        if (delta >= GRIND_CFG.contactDelta && this.motionRms(s.t) >= GRIND_CFG.minMotion) {
          this.phase = 'grinding';
          this.grindStart = s.t;
          this.lastContact = s.t;
          this.deltas = [delta];
          this.ev.onPhase?.('grinding');
          this.ev.onStart?.();
        }
        break;
      }
      case 'grinding': {
        this.ev.onLive?.(s.mag, delta);
        const moving = this.motionRms(s.t) >= GRIND_CFG.minMotion * 0.5;
        if (delta >= GRIND_CFG.releaseDelta && moving) {
          this.lastContact = s.t;
          this.deltas.push(delta);
          this.ev.onTick?.(Math.min(1, delta / GRIND_CFG.intensitySpan), delta);
        } else if (s.t - this.lastContact > GRIND_CFG.graceMs) {
          this.finish();
        }
        break;
      }
    }
  }

  /** Ends an active grind (rail lost, stop button, unmount). Safe to call anytime. */
  finish(): void {
    if (this.phase !== 'grinding') return;
    const durationMs = Math.max(0, this.lastContact - this.grindStart);
    this.phase = 'ready';
    this.ev.onPhase?.('ready');
    if (durationMs < GRIND_CFG.minGrindMs || this.deltas.length < 3) {
      this.ev.onEnd?.(null, durationMs);
      return;
    }
    const mean = this.deltas.reduce((a, b) => a + b, 0) / this.deltas.length;
    const sd = Math.sqrt(
      this.deltas.reduce((a, b) => a + (b - mean) ** 2, 0) / this.deltas.length,
    );
    const steadiness = Math.max(0, Math.min(1, 1 - sd / (mean || 1)));
    // Score = duration x steadiness: 2s of butter ≈ 100 points.
    const points = Math.round((durationMs / 1000) * 50 * (0.4 + 0.6 * steadiness));
    this.ev.onEnd?.(
      {
        durationMs,
        steadiness,
        avgDelta: mean,
        peakDelta: Math.max(...this.deltas),
        points,
      },
      durationMs,
    );
  }
}
