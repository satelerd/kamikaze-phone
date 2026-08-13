// Desktop simulator for Fridge Surfer: an IMU throw (via the shared generator)
// plus a synthetic mag stream that spikes right after the landing.
import { generateThrow } from '@/lib/sim';
import type { IMUSample, MagSample } from '@/lib/types';

export interface SurfFeed {
  imu: (s: IMUSample) => void;
  mag: (s: MagSample) => void;
  done?: () => void;
}

export interface SurfSimOpts {
  /** µT deviation after landing; below 35 = plastic table, above = magnet */
  magnetDelta?: number;
  airtime?: number;
}

export function simulateSurfThrow(feed: SurfFeed, opts: SurfSimOpts = {}): () => void {
  const airtime = opts.airtime ?? 0.8;
  const magnetDelta = opts.magnetDelta ?? 95;
  const leadInMs = 2800; // quiet hold that doubles as mag calibration time
  const imu = generateThrow({ airtime, spinsX: 2, leadInMs });
  const landT = leadInMs + 250 + airtime * 1000; // hold + windup + flight
  const baseline = 48;
  const mag: MagSample[] = [];
  const totalMs = landT + 2000;
  for (let t = 0; t <= totalMs; t += 40) {
    const onMagnet = t >= landT + 60;
    const m =
      baseline +
      (onMagnet ? magnetDelta + Math.sin(t / 90) * 6 : 0) +
      (Math.random() - 0.5) * 3;
    mag.push({ t, x: m, y: 0, z: 0, mag: Math.abs(m) });
  }
  return runFeeder(imu, mag, feed);
}

function runFeeder(imu: IMUSample[], mag: MagSample[], feed: SurfFeed): () => void {
  const start = performance.now();
  let iI = 0;
  let iM = 0;
  const iv = setInterval(() => {
    const now = performance.now() - start;
    while (iI < imu.length && imu[iI].t <= now) feed.imu(imu[iI++]);
    while (iM < mag.length && mag[iM].t <= now) feed.mag(mag[iM++]);
    if (iI >= imu.length && iM >= mag.length) {
      clearInterval(iv);
      feed.done?.();
    }
  }, 16);
  return () => clearInterval(iv);
}
