// Desktop simulator for Charger Bullseye: an IMU throw plus a synthetic
// battery charging flip shortly after the landing (or no flip = miss).
import { generateThrow } from '@/lib/sim';
import type { IMUSample } from '@/lib/types';

export interface BullseyeSimOpts {
  /** force hit/miss; default random 75% hit */
  hit?: boolean;
}

export function simulateBullseyeThrow(
  feedIMU: (s: IMUSample) => void,
  setCharging: (on: boolean) => void,
  opts: BullseyeSimOpts = {},
): () => void {
  const airtime = 0.7;
  const leadInMs = 700;
  const samples = generateThrow({ airtime, spinsX: 1.5, leadInMs });
  const hit = opts.hit ?? Math.random() < 0.75;
  const landMs = leadInMs + 250 + airtime * 1000;
  const timers: ReturnType<typeof setTimeout>[] = [];
  if (hit) {
    timers.push(setTimeout(() => setCharging(true), landMs + 400 + Math.random() * 900));
    timers.push(setTimeout(() => setCharging(false), landMs + 5000));
  }

  const start = performance.now();
  let i = 0;
  const iv = setInterval(() => {
    const now = performance.now() - start;
    while (i < samples.length && samples[i].t <= now) feedIMU(samples[i++]);
    if (i >= samples.length) clearInterval(iv);
  }, 16);

  return () => {
    clearInterval(iv);
    timers.forEach(clearTimeout);
  };
}
