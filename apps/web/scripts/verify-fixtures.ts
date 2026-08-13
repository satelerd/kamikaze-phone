// Parity check against the repository's reviewed motion evidence:
// replays fixtures/motion/v2 labelled captures (real iPhone 15 Plus throws)
// through the web ThrowTracker + classifier and compares against the
// recorded ground truth. Complements verify-physics.ts (synthetic), per the
// fixtures rule: synthetic data is never physical-device acceptance evidence.
// Run: npm run verify:fixtures
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ThrowTracker, extractFeatures, classifyThrow, type ThrowRecord } from '../src/lib/physics';
import type { IMUSample } from '../src/lib/types';

interface FixtureSample {
  timestampS: number;
  accelerationIncludingGravity: { x: number; y: number; z: number };
  rotationRateDps: { x: number; y: number; z: number };
}

interface LabelledCapture {
  schema: string;
  expectedTrick: string;
  ideal?: { rotation?: { x: number; y: number; z: number } };
  recordedAttempt: {
    airtimeMs: number;
    releaseTimestampS: number;
    catchTimestampS: number;
    rotationDegrees: { x: number; y: number; z: number; total: number };
    peakRotationDps: number;
    samples: FixtureSample[];
  };
}

const FIXTURE_DIR = join(__dirname, '..', '..', '..', 'fixtures', 'motion', 'v2', 'labelled');

function toIMU(samples: FixtureSample[]): IMUSample[] {
  const t0 = samples[0].timestampS;
  return samples.map((s) => ({
    t: (s.timestampS - t0) * 1000,
    ax: s.accelerationIncludingGravity.x,
    ay: s.accelerationIncludingGravity.y,
    az: s.accelerationIncludingGravity.z,
    // linear acceleration was not recorded; windup launch-speed integration
    // simply yields 0 and does not affect detection or rotation features
    lx: 0, ly: 0, lz: 0,
    rx: s.rotationRateDps.x,
    ry: s.rotationRateDps.y,
    rz: s.rotationRateDps.z,
  }));
}

let passes = 0;
let failures = 0;
function check(label: string, ok: boolean, detail = ''): void {
  if (ok) { passes++; console.log(`  ✓ ${label}${detail ? ` ${detail}` : ''}`); }
  else { failures++; console.error(`  ✗ ${label}${detail ? ` ${detail}` : ''}`); }
}

const files = readdirSync(FIXTURE_DIR).filter((f) => f.endsWith('.json'));
if (!files.length) {
  console.error(`No fixtures found in ${FIXTURE_DIR}`);
  process.exit(1);
}

for (const file of files) {
  const cap = JSON.parse(readFileSync(join(FIXTURE_DIR, file), 'utf8')) as LabelledCapture;
  console.log(`\n${file}`);
  console.log(`  labelled: ${cap.expectedTrick}, recorded rotation ` +
    `x=${cap.recordedAttempt.rotationDegrees.x.toFixed(0)} y=${cap.recordedAttempt.rotationDegrees.y.toFixed(0)} z=${cap.recordedAttempt.rotationDegrees.z.toFixed(0)}`);

  const samples = toIMU(cap.recordedAttempt.samples);
  let record: ThrowRecord | null = null;
  const tracker = new ThrowTracker((rec) => { record = rec; });
  samples.forEach((s) => tracker.feed(s));

  // The capture window ends at the catch; if the tracker is still in its
  // settle window when samples run out, flush by feeding a short calm tail.
  if (!record) {
    const last = samples[samples.length - 1];
    for (let i = 1; i <= 60; i++) {
      tracker.feed({ ...last, t: last.t + i * 10, ax: 0, ay: 0, az: 9.81, rx: 0, ry: 0, rz: 0 });
    }
  }

  check('throw detected from real capture', !!record);
  if (!record) continue;
  const rec: ThrowRecord = record;
  const f = extractFeatures(rec);
  const result = classifyThrow(rec);

  // Rotation parity: our per-axis integration vs the attempt's recorded
  // totals (their integration runs release→catch; ours runs the detected
  // freefall window, so allow 25% or 60° slack, whichever is larger).
  const g = cap.recordedAttempt.rotationDegrees;
  (['x', 'y', 'z'] as const).forEach((axis) => {
    const ours = axis === 'x' ? f.rotX : axis === 'y' ? f.rotY : f.rotZ;
    const theirs = g[axis];
    const tol = Math.max(60, Math.abs(theirs) * 0.25);
    check(
      `rotation ${axis} within tolerance of recorded ${theirs.toFixed(0)}°`,
      Math.abs(ours - theirs) <= tol,
      `→ ours ${ours.toFixed(0)}°`,
    );
  });

  // Airtime sanity: our freefall window must fit inside the release→catch
  // window and cover a meaningful share of it.
  const windowS = cap.recordedAttempt.catchTimestampS - cap.recordedAttempt.releaseTimestampS;
  check(
    `airtime ${f.airtime.toFixed(2)}s inside recorded window ${windowS.toFixed(2)}s`,
    f.airtime > 0.15 && f.airtime <= windowS + 0.1,
  );

  console.log(`  classified: ${result.trickName} (${result.trickId}), grade ${result.grade}, ` +
    `spins x=${(f.rotX / 360).toFixed(2)} y=${(f.rotY / 360).toFixed(2)} z=${(f.rotZ / 360).toFixed(2)}`);
}

console.log(`\n${'='.repeat(50)}\n${passes} passed, ${failures} failed`);
if (failures > 0) process.exit(1);
