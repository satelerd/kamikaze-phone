// Desktop simulator for Scream Meter: fake mic levels for the hype window and
// an IMU throw with a whoosh burst timed mid-flight, all through the same
// handlers the real mic/sensors use.
import { generateThrow } from '@/lib/sim';
import type { IMUSample } from '@/lib/types';
import { rmsToDb, type MicLevel } from './logic';

/** 3s of synthetic scream levels; calls done(peakDb) at the end. Returns cancel(). */
export function simulateScreamLevels(
  onLevel: (lv: MicLevel) => void,
  done: (peakDb: number) => void,
): () => void {
  const start = performance.now();
  const peakRms = 0.2 + Math.random() * 0.75;
  const iv = setInterval(() => {
    const k = (performance.now() - start) / 3000;
    if (k >= 1) {
      clearInterval(iv);
      done(rmsToDb(peakRms));
      return;
    }
    const envelope = Math.sin(Math.PI * Math.min(1, k * 1.15)) ** 1.5;
    const rms = Math.max(0.02, envelope * peakRms * (0.75 + Math.random() * 0.25));
    onLevel({ rms, db: rmsToDb(rms) });
  }, 50);
  return () => clearInterval(iv);
}

export interface ScreamThrowFeed {
  imu: (s: IMUSample) => void;
  level: (lv: MicLevel) => void;
  done?: () => void;
}

/** IMU throw + a whoosh burst in the mic levels mid-flight. Returns cancel(). */
export function simulateScreamThrow(feed: ScreamThrowFeed): () => void {
  const airtime = 0.85;
  const leadInMs = 500;
  const imu = generateThrow({ airtime, spinsX: 2, leadInMs });
  const launchT = leadInMs + 250;
  const landT = launchT + airtime * 1000;
  const whooshFrom = launchT + airtime * 250;
  const whooshTo = launchT + airtime * 600;
  const totalMs = landT + 1200;

  const start = performance.now();
  let iI = 0;
  let lastLevel = 0;
  const iv = setInterval(() => {
    const now = performance.now() - start;
    while (iI < imu.length && imu[iI].t <= now) feed.imu(imu[iI++]);
    while (lastLevel + 50 <= now) {
      lastLevel += 50;
      const inWhoosh = lastLevel >= whooshFrom && lastLevel <= whooshTo;
      const rms = inWhoosh ? 0.12 + Math.random() * 0.06 : 0.015 + Math.random() * 0.01;
      feed.level({ rms, db: rmsToDb(rms) });
    }
    if (iI >= imu.length && now >= totalMs) {
      clearInterval(iv);
      feed.done?.();
    }
  }, 16);
  return () => clearInterval(iv);
}
