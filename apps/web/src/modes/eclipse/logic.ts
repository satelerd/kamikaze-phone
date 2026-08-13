// Eclipse: record ambient light during a throw and score the darkness dip.
// The recorder keeps a rolling lux buffer plus a trailing baseline that only
// updates while the phone is not in flight.
import type { LuxSample } from '@/lib/types';

export interface EclipseVerdict {
  baseline: number;
  minLux: number;
  /** 0..1: how much of the ambient light got eaten mid-flight */
  dipRatio: number;
  /** lux < 2 during flight while ambient baseline > 50 */
  fullBlackout: boolean;
  bonus: number;
  /** lux slice around the flight for the strip chart */
  chart: LuxSample[];
  samples: number;
}

export const ECLIPSE_CFG = {
  blackoutLux: 2,
  blackoutMinBaseline: 50,
  dipBonusMax: 60,
  blackoutBonus: 40,
  /** safety: auto-clear inFlight if no landing ever arrives */
  maxFlightMs: 4000,
};

export class LuxRecorder {
  baseline = 0;
  private buffer: LuxSample[] = [];
  private baselineWindow: LuxSample[] = [];
  private inFlight = false;
  private flightStartT = -1;

  feedLux(s: LuxSample): void {
    this.buffer.push(s);
    while (this.buffer.length && this.buffer[0].t < s.t - 15000) this.buffer.shift();

    if (this.inFlight) {
      if (this.flightStartT < 0) this.flightStartT = s.t;
      else if (s.t - this.flightStartT > ECLIPSE_CFG.maxFlightMs) this.inFlight = false;
      return;
    }
    this.baselineWindow.push(s);
    while (this.baselineWindow.length && this.baselineWindow[0].t < s.t - 3000) {
      this.baselineWindow.shift();
    }
    if (this.baselineWindow.length >= 3) {
      const sorted = this.baselineWindow.map((l) => l.lux).sort((a, b) => a - b);
      this.baseline = sorted[Math.floor(sorted.length / 2)];
    }
  }

  /** Freeze baseline updates while airborne (the dip must not poison it). */
  setInFlight(v: boolean): void {
    this.inFlight = v;
    if (v) this.flightStartT = -1;
  }

  judge(launchT: number, landT: number): EclipseVerdict {
    const chart = this.buffer.filter((l) => l.t >= launchT - 250 && l.t <= landT + 250);
    const flight = this.buffer.filter((l) => l.t >= launchT && l.t <= landT);
    const minLux = flight.length ? Math.min(...flight.map((l) => l.lux)) : this.baseline;
    const dipRatio =
      this.baseline > 0 ? Math.max(0, Math.min(1, 1 - minLux / this.baseline)) : 0;
    const fullBlackout =
      flight.length > 0 &&
      minLux < ECLIPSE_CFG.blackoutLux &&
      this.baseline > ECLIPSE_CFG.blackoutMinBaseline;
    const bonus =
      Math.round(dipRatio * ECLIPSE_CFG.dipBonusMax) +
      (fullBlackout ? ECLIPSE_CFG.blackoutBonus : 0);
    return {
      baseline: this.baseline,
      minLux,
      dipRatio,
      fullBlackout,
      bonus,
      chart,
      samples: flight.length,
    };
  }
}
