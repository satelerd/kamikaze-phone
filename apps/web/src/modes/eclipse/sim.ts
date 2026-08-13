// Desktop simulator for Eclipse: an IMU throw plus a lux stream that plunges
// into darkness during the flight window (a throw through a shadow tunnel).
import { generateThrow } from '@/lib/sim';
import type { IMUSample, LuxSample } from '@/lib/types';

export interface EclipseFeed {
  imu: (s: IMUSample) => void;
  lux: (s: LuxSample) => void;
  done?: () => void;
}

export interface EclipseSimOpts {
  /** ambient light before/after the throw */
  ambient?: number;
  /** darkest lux mid-flight; < 2 with ambient > 50 = full blackout */
  darkest?: number;
  airtime?: number;
}

export function simulateEclipseThrow(feed: EclipseFeed, opts: EclipseSimOpts = {}): () => void {
  const ambient = opts.ambient ?? 140;
  const darkest = opts.darkest ?? 0.8;
  const airtime = opts.airtime ?? 1.0;
  const leadInMs = 900;
  const imu = generateThrow({ airtime, spinsX: 1.5, leadInMs });
  const launchT = leadInMs + 250;
  const landT = launchT + airtime * 1000;
  const lux: LuxSample[] = [];
  const totalMs = landT + 1500;
  for (let t = 0; t <= totalMs; t += 50) {
    const inShadow = t >= launchT + 120 && t <= landT - 120;
    const v = inShadow
      ? Math.max(0, darkest + Math.random() * 0.7)
      : ambient + (Math.random() - 0.5) * 10;
    lux.push({ t, lux: v });
  }
  return runFeeder(imu, lux, feed);
}

function runFeeder(imu: IMUSample[], lux: LuxSample[], feed: EclipseFeed): () => void {
  const start = performance.now();
  let iI = 0;
  let iL = 0;
  const iv = setInterval(() => {
    const now = performance.now() - start;
    while (iI < imu.length && imu[iI].t <= now) feed.imu(imu[iI++]);
    while (iL < lux.length && lux[iL].t <= now) feed.lux(lux[iL++]);
    if (iI >= imu.length && iL >= lux.length) {
      clearInterval(iv);
      feed.done?.();
    }
  }, 16);
  return () => clearInterval(iv);
}
