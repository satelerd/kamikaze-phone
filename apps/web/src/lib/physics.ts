// Throw physics: sensor-fusion trajectory reconstruction + trick classification.
// Pure TypeScript, no DOM dependencies, so it runs under Node for verification
// (`npm run verify:physics`) and in the browser.
import type {
  GameEvent, IMUSample, StyleScore, ThrowPhase, TrajectoryPoint, TrickFeatures, TrickResult,
} from './types';

export const G = 9.81;

// ---------------------------------------------------------------------------
// Quaternion helpers (orientation integration from gyro)
// ---------------------------------------------------------------------------
export type Quat = { w: number; x: number; y: number; z: number };

export const QUAT_IDENTITY: Quat = { w: 1, x: 0, y: 0, z: 0 };

export function quatMultiply(a: Quat, b: Quat): Quat {
  return {
    w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
    y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
    z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
  };
}

export function quatNormalize(q: Quat): Quat {
  const n = Math.hypot(q.w, q.x, q.y, q.z) || 1;
  return { w: q.w / n, x: q.x / n, y: q.y / n, z: q.z / n };
}

/** Integrate body-frame angular velocity (deg/s) over dt seconds. */
export function quatIntegrate(q: Quat, rxDeg: number, ryDeg: number, rzDeg: number, dt: number): Quat {
  const rx = (rxDeg * Math.PI) / 180;
  const ry = (ryDeg * Math.PI) / 180;
  const rz = (rzDeg * Math.PI) / 180;
  const omega = Math.hypot(rx, ry, rz);
  if (omega < 1e-9) return q;
  const half = (omega * dt) / 2;
  const s = Math.sin(half) / omega;
  const dq: Quat = { w: Math.cos(half), x: rx * s, y: ry * s, z: rz * s };
  return quatNormalize(quatMultiply(q, dq));
}

/** Rotate a vector from device frame to world frame with quaternion q. */
export function rotateVec(q: Quat, v: [number, number, number]): [number, number, number] {
  const { w, x, y, z } = q;
  const [vx, vy, vz] = v;
  // t = 2 * cross(q.xyz, v)
  const tx = 2 * (y * vz - z * vy);
  const ty = 2 * (z * vx - x * vz);
  const tz = 2 * (x * vy - y * vx);
  return [
    vx + w * tx + (y * tz - z * ty),
    vy + w * ty + (z * tx - x * tz),
    vz + w * tz + (x * ty - y * tx),
  ];
}

// ---------------------------------------------------------------------------
// Phase detection state machine
// ---------------------------------------------------------------------------
export interface PhaseConfig {
  /** |a_total| below this = freefall (m/s²). Real sensors are noisy: ~3 works. */
  freefallThreshold: number;
  /** |a_total| above this = impact (m/s²) */
  impactThreshold: number;
  /** minimum ms in freefall to count as a throw (filters hand jiggle) */
  minAirtimeMs: number;
  /** ms of calm after impact to consider the phone held */
  settleWindowMs: number;
  settleThreshold: number;
}

export const DEFAULT_PHASE_CONFIG: PhaseConfig = {
  freefallThreshold: 3.0,
  impactThreshold: 25.0,
  minAirtimeMs: 150,
  settleWindowMs: 400,
  settleThreshold: 12.0,
};

export interface ThrowRecord {
  windup: IMUSample[];
  flight: IMUSample[];
  landing: IMUSample[];
  launchT: number;
  landT: number;
  settleMs: number;
  caught: boolean;
}

/**
 * Streaming throw detector. Feed IMU samples; emits phase changes, per-flip
 * events (for FX) and a complete ThrowRecord when a throw finishes.
 */
export class ThrowTracker {
  phase: ThrowPhase = 'idle';
  private cfg: PhaseConfig;
  private history: IMUSample[] = [];
  private flight: IMUSample[] = [];
  private landing: IMUSample[] = [];
  private launchT = 0;
  private impactT = 0;
  private impactPeak = 0;
  private accumRotDeg = 0;
  private flipsEmitted = 0;
  private events: GameEvent[] = [];
  private onThrow: (rec: ThrowRecord) => void;
  private onEvent: (e: GameEvent) => void;

  constructor(
    onThrow: (rec: ThrowRecord) => void,
    onEvent: (e: GameEvent) => void = () => {},
    cfg: PhaseConfig = DEFAULT_PHASE_CONFIG,
  ) {
    this.onThrow = onThrow;
    this.onEvent = onEvent;
    this.cfg = cfg;
  }

  feed(s: IMUSample): void {
    const aTotal = Math.hypot(s.ax, s.ay, s.az);
    this.history.push(s);
    if (this.history.length > 600) this.history.splice(0, this.history.length - 600);

    switch (this.phase) {
      case 'idle':
      case 'held': {
        if (aTotal < this.cfg.freefallThreshold) {
          this.phase = 'airborne';
          this.launchT = s.t;
          this.flight = [s];
          this.landing = [];
          this.accumRotDeg = 0;
          this.flipsEmitted = 0;
          this.impactPeak = 0;
          this.onEvent({ type: 'launch' });
        }
        break;
      }
      case 'airborne': {
        this.flight.push(s);
        const dt = this.flight.length > 1 ? (s.t - this.flight[this.flight.length - 2].t) / 1000 : 0;
        this.accumRotDeg += Math.hypot(s.rx, s.ry, s.rz) * dt;
        // 330°/flip: real sensors undercount slightly (first/last flight sample
        // carries no dt), and FX ticks should fire as the flip completes.
        const flips = Math.floor(this.accumRotDeg / 330);
        if (flips > this.flipsEmitted) {
          this.flipsEmitted = flips;
          this.onEvent({ type: 'flip', count: flips });
        }
        if (aTotal > this.cfg.impactThreshold) {
          this.phase = 'impact';
          this.impactT = s.t;
          this.impactPeak = aTotal;
          this.landing = [s];
        }
        break;
      }
      case 'impact': {
        this.landing.push(s);
        this.impactPeak = Math.max(this.impactPeak, aTotal);
        // Back to freefall = it bounced / got popped up again mid-record.
        if (aTotal < this.cfg.freefallThreshold && s.t - this.impactT > 80) {
          this.phase = 'airborne';
          this.flight.push(...this.landing);
          this.landing = [];
          break;
        }
        if (s.t - this.impactT >= this.cfg.settleWindowMs) {
          const airtimeMs = this.impactT - this.launchT;
          const recent = this.landing.filter((l) => l.t > s.t - 200);
          const calm =
            recent.length > 0 &&
            recent.every((l) => Math.hypot(l.ax, l.ay, l.az) < this.cfg.settleThreshold);
          this.phase = 'held';
          if (airtimeMs >= this.cfg.minAirtimeMs) {
            const windup = this.history.filter((h) => h.t >= this.launchT - 500 && h.t < this.launchT);
            this.onEvent({ type: 'catch', clean: calm, impactG: this.impactPeak });
            this.onThrow({
              windup,
              flight: this.flight.slice(),
              landing: this.landing.slice(),
              launchT: this.launchT,
              landT: this.impactT,
              settleMs: s.t - this.impactT,
              caught: calm,
            });
          }
        }
        break;
      }
      case 'windup':
        break;
    }
  }

  reset(): void {
    this.phase = 'idle';
    this.flight = [];
    this.landing = [];
    this.history = [];
  }
}

// ---------------------------------------------------------------------------
// Trajectory reconstruction (accelerometer + gyro fusion)
// ---------------------------------------------------------------------------

/**
 * Reconstruct a world-frame trajectory for a throw.
 *
 * Vertical: ballistic from airtime (exact under freefall: rise = g·T²/8).
 * Horizontal: launch velocity integrated from windup linear acceleration,
 * rotated into world frame via gyro-integrated orientation. Orientation along
 * the flight comes from integrating rotationRate per sample.
 */
export function reconstructTrajectory(rec: ThrowRecord): TrajectoryPoint[] {
  const T = (rec.landT - rec.launchT) / 1000;
  if (T <= 0 || rec.flight.length < 2) return [];

  // Launch velocity from windup: integrate linear acceleration (device frame),
  // rotated by integrated orientation, over the last 300ms before release.
  let q: Quat = QUAT_IDENTITY;
  let vx = 0, vz = 0;
  for (let i = 1; i < rec.windup.length; i++) {
    const s = rec.windup[i];
    const dt = (s.t - rec.windup[i - 1].t) / 1000;
    if (dt <= 0 || dt > 0.1) continue;
    q = quatIntegrate(q, s.rx, s.ry, s.rz, dt);
    const [wx, , wz] = rotateVec(q, [s.lx, s.ly, s.lz]);
    vx += wx * dt;
    vz += wz * dt;
  }
  // Vertical launch speed from ballistics: v0 = g·T/2 (up = +y).
  const vy0 = (G * T) / 2;

  const points: TrajectoryPoint[] = [];
  q = QUAT_IDENTITY;
  let prevT = rec.flight[0].t;
  for (const s of rec.flight) {
    const dt = (s.t - prevT) / 1000;
    prevT = s.t;
    q = quatIntegrate(q, s.rx, s.ry, s.rz, dt);
    const t = (s.t - rec.launchT) / 1000;
    points.push({
      t: s.t - rec.launchT,
      x: vx * t,
      y: vy0 * t - 0.5 * G * t * t,
      z: vz * t,
      qw: q.w, qx: q.x, qy: q.y, qz: q.z,
    });
  }
  return points;
}

export function extractFeatures(rec: ThrowRecord): TrickFeatures {
  const T = (rec.landT - rec.launchT) / 1000;
  let rotX = 0, rotY = 0, rotZ = 0;
  const rates: number[] = [];
  for (let i = 1; i < rec.flight.length; i++) {
    const s = rec.flight[i];
    const dt = (s.t - rec.flight[i - 1].t) / 1000;
    if (dt <= 0 || dt > 0.1) continue;
    rotX += s.rx * dt;
    rotY += s.ry * dt;
    rotZ += s.rz * dt;
    rates.push(Math.hypot(s.rx, s.ry, s.rz));
  }
  const mean = rates.length ? rates.reduce((a, b) => a + b, 0) / rates.length : 0;
  const wobble = rates.length
    ? Math.sqrt(rates.reduce((a, b) => a + (b - mean) ** 2, 0) / rates.length)
    : 0;

  const abs = { x: Math.abs(rotX), y: Math.abs(rotY), z: Math.abs(rotZ) };
  const total = abs.x + abs.y + abs.z || 1;
  const dominantAxis = abs.x >= abs.y && abs.x >= abs.z ? 'x' : abs.y >= abs.z ? 'y' : 'z';
  const axisPurity = abs[dominantAxis] / total;

  let launchSpeed = 0;
  let q: Quat = QUAT_IDENTITY;
  let lvx = 0, lvy = 0, lvz = 0;
  for (let i = 1; i < rec.windup.length; i++) {
    const s = rec.windup[i];
    const dt = (s.t - rec.windup[i - 1].t) / 1000;
    if (dt <= 0 || dt > 0.1) continue;
    q = quatIntegrate(q, s.rx, s.ry, s.rz, dt);
    const [wx, wy, wz] = rotateVec(q, [s.lx, s.ly, s.lz]);
    lvx += wx * dt; lvy += wy * dt; lvz += wz * dt;
  }
  launchSpeed = Math.hypot(lvx, lvy, lvz);

  let impactG = 0;
  for (const s of rec.landing) impactG = Math.max(impactG, Math.hypot(s.ax, s.ay, s.az));

  return {
    airtime: T,
    height: (G * T * T) / 8,
    rotX, rotY, rotZ,
    axisPurity,
    dominantAxis,
    wobble,
    impactG,
    settleMs: rec.settleMs,
    launchSpeed,
    caught: rec.caught,
  };
}

// ---------------------------------------------------------------------------
// Trick library + classifier
// ---------------------------------------------------------------------------
export interface TrickDef {
  id: string;
  name: string;
  callout: string;
  base: number;
  match: (f: TrickFeatures) => boolean;
}

const spins = (f: TrickFeatures) =>
  Math.max(Math.abs(f.rotX), Math.abs(f.rotY), Math.abs(f.rotZ)) / 360;

/** Ordered: first match wins, most specific first. */
export const TRICK_LIBRARY: TrickDef[] = [
  {
    id: 'corkscrew', name: 'Corkscrew', base: 55,
    callout: 'Corkscrew!? That thing was a blender, dude!',
    match: (f) => spins(f) >= 1 && f.axisPurity < 0.6,
  },
  {
    id: 'helicopter-triple', name: 'Triple Helicopter', base: 85,
    callout: 'TRIPLE HELI! Call the airport, brah!',
    match: (f) => f.dominantAxis === 'z' && Math.abs(f.rotZ) >= 3 * 330 && f.axisPurity >= 0.6,
  },
  {
    id: 'helicopter-double', name: 'Double Helicopter', base: 60,
    callout: 'Double heli, twin rotors engaged!',
    match: (f) => f.dominantAxis === 'z' && Math.abs(f.rotZ) >= 2 * 330 && f.axisPurity >= 0.6,
  },
  {
    id: 'helicopter', name: 'Helicopter', base: 40,
    callout: 'UFO spin! The saucer has landed.',
    match: (f) => f.dominantAxis === 'z' && Math.abs(f.rotZ) >= 300 && f.axisPurity >= 0.6,
  },
  {
    id: 'barrel-triple', name: 'Triple Barrel Roll', base: 85,
    callout: 'TRIPLE BARREL! Pipeline material, no doubt!',
    match: (f) => f.dominantAxis === 'y' && Math.abs(f.rotY) >= 3 * 330 && f.axisPurity >= 0.6,
  },
  {
    id: 'barrel-double', name: 'Double Barrel Roll', base: 60,
    callout: 'Double barrel, locked and loaded!',
    match: (f) => f.dominantAxis === 'y' && Math.abs(f.rotY) >= 2 * 330 && f.axisPurity >= 0.6,
  },
  {
    id: 'barrel', name: 'Barrel Roll', base: 40,
    callout: 'Do a barrel roll! Oh wait, you just did.',
    match: (f) => f.dominantAxis === 'y' && Math.abs(f.rotY) >= 300 && f.axisPurity >= 0.6,
  },
  {
    id: 'pancake-triple', name: 'Triple Pancake', base: 90,
    callout: 'TRIPLE PANCAKE! IHOP is calling, they want their flip back!',
    match: (f) => f.dominantAxis === 'x' && Math.abs(f.rotX) >= 3 * 330 && f.axisPurity >= 0.6,
  },
  {
    id: 'pancake-double', name: 'Double Pancake', base: 62,
    callout: 'Double stack! Syrup on that flip!',
    match: (f) => f.dominantAxis === 'x' && Math.abs(f.rotX) >= 2 * 330 && f.axisPurity >= 0.6,
  },
  {
    id: 'pancake', name: 'Pancake Flip', base: 40,
    callout: 'Classic pancake, golden on both sides!',
    match: (f) => f.dominantAxis === 'x' && Math.abs(f.rotX) >= 300 && f.axisPurity >= 0.6,
  },
  {
    id: 'moonshot', name: 'Moonshot', base: 50,
    callout: 'MOONSHOT! Houston, the eagle is airborne!',
    match: (f) => f.height >= 1.5 && spins(f) < 1,
  },
  {
    id: 'zen-toss', name: 'Zen Toss', base: 30,
    callout: 'Zen toss. No spin, all soul.',
    match: (f) => spins(f) < 0.35 && f.wobble < 80 && f.airtime >= 0.35,
  },
  {
    id: 'wobbler', name: 'The Wobbler', base: 15,
    callout: 'Whoa, sketchy! That phone was tumbling like laundry.',
    match: () => true, // fallback
  },
];

function clamp(n: number, lo = 0, hi = 100): number {
  return Math.max(lo, Math.min(hi, n));
}

export function scoreThrow(f: TrickFeatures): { style: StyleScore; score: number; grade: TrickResult['grade'] } {
  const style: StyleScore = {
    amplitude: clamp((f.height / 2.5) * 100),
    rotation: clamp(spins(f) * 33),
    cleanliness: clamp(f.axisPurity * 100 - Math.min(40, f.wobble / 6)),
    catch: f.caught ? clamp(100 - Math.max(0, f.impactG - 25) * 1.5 - Math.max(0, f.settleMs - 300) / 10) : 0,
    commitment: clamp((f.airtime / 1.4) * 70 + (f.launchSpeed / 5) * 30),
  };
  const score = Math.round(
    style.amplitude * 0.24 + style.rotation * 0.24 + style.cleanliness * 0.2 +
    style.catch * 0.22 + style.commitment * 0.1,
  );
  const grade: TrickResult['grade'] = !f.caught
    ? 'BAIL'
    : score >= 85 ? 'S' : score >= 65 ? 'A' : score >= 40 ? 'B' : 'C';
  return { style, score, grade };
}

export function classifyThrow(rec: ThrowRecord, mode = 'free-ride'): TrickResult {
  const features = extractFeatures(rec);
  const trick = TRICK_LIBRARY.find((t) => t.match(features)) ?? TRICK_LIBRARY[TRICK_LIBRARY.length - 1];
  const { style, score, grade } = scoreThrow(features);
  return {
    id: `throw-${rec.launchT.toFixed(0)}`,
    trickId: trick.id,
    trickName: trick.name,
    callout: trick.callout,
    features,
    style,
    score,
    grade,
    trajectory: reconstructTrajectory(rec),
    at: Date.now(),
    mode,
  };
}
