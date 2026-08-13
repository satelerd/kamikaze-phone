// Desktop simulator for Rail Grind: synthesizes a mag + IMU stream shaped like
// calibration hold → approach → 2.6s wobbly grind → release.
import type { IMUSample, MagSample } from '@/lib/types';

export interface GrindFeed {
  imu: (s: IMUSample) => void;
  mag: (s: MagSample) => void;
  done?: () => void;
}

const TOTAL_MS = 7600;
const GRIND_FROM = 3900;
const GRIND_TO = 6500;

function imuAt(t: number): IMUSample {
  const grinding = t >= GRIND_FROM && t < GRIND_TO;
  const approaching = t >= 3200 && t < GRIND_FROM;
  const jitter = grinding ? 1.6 : approaching ? 0.8 : 0.05;
  const lx = (Math.random() - 0.5) * 2 * jitter + (grinding ? Math.sin(t / 40) * 0.8 : 0);
  const ly = (Math.random() - 0.5) * 2 * jitter;
  const lz = (Math.random() - 0.5) * jitter;
  return {
    t,
    ax: lx, ay: ly, az: 9.81 + lz,
    lx, ly, lz,
    rx: (Math.random() - 0.5) * 8,
    ry: (Math.random() - 0.5) * 8,
    rz: (Math.random() - 0.5) * 8,
  };
}

function magAt(t: number): MagSample {
  const baseline = 49;
  let m = baseline + (Math.random() - 0.5) * 2.5;
  if (t >= GRIND_FROM && t < GRIND_TO) {
    const ramp = Math.min(1, (t - GRIND_FROM) / 250) * Math.min(1, (GRIND_TO - t) / 250);
    m = baseline + ramp * (85 + Math.sin(t / 300) * 40 + (Math.random() - 0.5) * 10);
  }
  return { t, x: m, y: 0, z: 0, mag: m };
}

/** Feeds a full synthetic grind session in real time. Returns cancel(). */
export function simulateGrindSession(feed: GrindFeed): () => void {
  const start = performance.now();
  let lastImu = 0;
  let lastMag = 0;
  const iv = setInterval(() => {
    const t = performance.now() - start;
    if (t >= TOTAL_MS) {
      clearInterval(iv);
      feed.done?.();
      return;
    }
    while (lastImu + 20 <= t) {
      lastImu += 20;
      feed.imu(imuAt(lastImu));
    }
    while (lastMag + 40 <= t) {
      lastMag += 40;
      feed.mag(magAt(lastMag));
    }
  }, 16);
  return () => clearInterval(iv);
}
