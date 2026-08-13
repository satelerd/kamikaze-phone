// Synthetic throw generator: desktop demo mode + physics verification.
// Produces IMU streams shaped like a real hand-toss: hold → windup → freefall
// (|a|≈0, spinning) → impact spike → settle.
import type { IMUSample } from './types';
import { G } from './physics';

export interface SimThrowParams {
  /** seconds of freefall */
  airtime: number;
  /** full rotations around each device axis during flight */
  spinsX?: number;
  spinsY?: number;
  spinsZ?: number;
  /** m/s² gyro/accel noise scale */
  noise?: number;
  /** how hard the catch is (peak m/s²) */
  impactG?: number;
  /** whether the catch settles cleanly */
  clean?: boolean;
  sampleHz?: number;
  /** ms of quiet hold before the windup */
  leadInMs?: number;
}

let seed = 42;
function rand(): number {
  // deterministic LCG so verification is reproducible
  seed = (seed * 1664525 + 1013904223) % 4294967296;
  return seed / 4294967296 - 0.5;
}

export function resetSimSeed(s = 42): void {
  seed = s;
}

export function generateThrow(p: SimThrowParams, t0 = 0): IMUSample[] {
  const hz = p.sampleHz ?? 100;
  const dt = 1000 / hz;
  const noise = p.noise ?? 0.15;
  const impactG = p.impactG ?? 45;
  const samples: IMUSample[] = [];
  let t = t0;

  const push = (ax: number, ay: number, az: number, lx: number, ly: number, lz: number, rx: number, ry: number, rz: number) => {
    samples.push({
      t,
      ax: ax + rand() * noise, ay: ay + rand() * noise, az: az + rand() * noise,
      lx: lx + rand() * noise, ly: ly + rand() * noise, lz: lz + rand() * noise,
      rx: rx + rand() * noise * 20, ry: ry + rand() * noise * 20, rz: rz + rand() * noise * 20,
    });
    t += dt;
  };

  // 1. hold: gravity on z, still
  for (let ms = 0; ms < (p.leadInMs ?? 600); ms += dt) push(0, 0, G, 0, 0, 0, 0, 0, 0);

  // 2. windup: 250ms upward push (linear accel on y up to launch speed)
  const windupMs = 250;
  const vLaunch = (G * p.airtime) / 2;
  const aWindup = vLaunch / (windupMs / 1000);
  for (let ms = 0; ms < windupMs; ms += dt) push(0, aWindup, G, 0, aWindup, 0, 20, 0, 0);

  // 3. freefall: |a| ≈ 0, constant spin
  const flightMs = p.airtime * 1000;
  const rateX = ((p.spinsX ?? 0) * 360) / p.airtime;
  const rateY = ((p.spinsY ?? 0) * 360) / p.airtime;
  const rateZ = ((p.spinsZ ?? 0) * 360) / p.airtime;
  for (let ms = 0; ms < flightMs; ms += dt) push(0, 0, 0, 0, 0, 0, rateX, rateY, rateZ);

  // 4. impact spike (~60ms)
  for (let ms = 0; ms < 60; ms += dt) {
    const k = 1 - ms / 60;
    push(0, -impactG * k, G, 0, -impactG * k, 0, 40 * k, 30 * k, 20 * k);
  }

  // 5. settle: clean = calm hold; dirty = juggling bobbles
  for (let ms = 0; ms < 600; ms += dt) {
    if (p.clean === false && ms < 350) {
      const bump = 14 + 8 * Math.sin(ms / 25);
      push(0, bump, G, 0, bump, 0, 90, 70, 50);
    } else {
      push(0, 0, G, 0, 0, 0, 0, 0, 0);
    }
  }
  return samples;
}

/** A ready-made highlight reel for the desktop demo. */
export function demoSession(): { label: string; params: SimThrowParams }[] {
  return [
    { label: 'Warm-up toss', params: { airtime: 0.5, spinsX: 1 } },
    { label: 'Double pancake', params: { airtime: 0.8, spinsX: 2 } },
    { label: 'Helicopter', params: { airtime: 0.7, spinsZ: 1.2 } },
    { label: 'Moonshot', params: { airtime: 1.3, spinsX: 0.2 } },
    { label: 'Corkscrew chaos', params: { airtime: 0.9, spinsX: 1.2, spinsY: 1.1, noise: 0.6 } },
    { label: 'The bail', params: { airtime: 0.6, spinsX: 1, clean: false, impactG: 70 } },
  ];
}
