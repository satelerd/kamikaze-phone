// Physics verification harness: synthetic IMU throws with known ground truth
// must be detected, reconstructed and classified correctly.
// Run: npm run verify:physics
import { ThrowTracker, classifyThrow, type ThrowRecord } from '../src/lib/physics';
import { generateThrow, resetSimSeed, type SimThrowParams } from '../src/lib/sim';

interface Case {
  name: string;
  params: SimThrowParams;
  expectTrick: string | string[];
  expectAirtime?: number;
  expectCaught?: boolean;
  minFlips?: number;
}

const CASES: Case[] = [
  { name: 'single pancake', params: { airtime: 0.6, spinsX: 1 }, expectTrick: 'pancake', expectAirtime: 0.6, minFlips: 1 },
  { name: 'double pancake', params: { airtime: 0.85, spinsX: 2 }, expectTrick: 'pancake-double', expectAirtime: 0.85, minFlips: 2 },
  { name: 'triple pancake', params: { airtime: 1.1, spinsX: 3 }, expectTrick: 'pancake-triple', minFlips: 3 },
  { name: 'barrel roll', params: { airtime: 0.6, spinsY: 1 }, expectTrick: 'barrel' },
  { name: 'double barrel', params: { airtime: 0.8, spinsY: 2 }, expectTrick: 'barrel-double' },
  { name: 'helicopter', params: { airtime: 0.6, spinsZ: 1 }, expectTrick: 'helicopter' },
  { name: 'triple helicopter', params: { airtime: 1.0, spinsZ: 3 }, expectTrick: 'helicopter-triple' },
  { name: 'moonshot (big air, no spin)', params: { airtime: 1.4, spinsX: 0.2 }, expectTrick: 'moonshot', expectAirtime: 1.4 },
  { name: 'zen toss', params: { airtime: 0.5, spinsX: 0.1, noise: 0.05 }, expectTrick: 'zen-toss' },
  { name: 'corkscrew (mixed axes)', params: { airtime: 0.9, spinsX: 1.2, spinsY: 1.1 }, expectTrick: 'corkscrew' },
  { name: 'dirty catch = bail grade', params: { airtime: 0.7, spinsX: 1, clean: false, impactG: 70 }, expectTrick: ['pancake'], expectCaught: false },
];

let failures = 0;
let passes = 0;

function check(label: string, ok: boolean, detail = ''): void {
  if (ok) {
    passes++;
    console.log(`  ✓ ${label}${detail ? ` ${detail}` : ''}`);
  } else {
    failures++;
    console.error(`  ✗ ${label}${detail ? ` ${detail}` : ''}`);
  }
}

for (const c of CASES) {
  console.log(`\n${c.name}`);
  resetSimSeed(1234);
  const samples = generateThrow(c.params);
  let record: ThrowRecord | null = null;
  let flipEvents = 0;
  const tracker = new ThrowTracker(
    (rec) => { record = rec; },
    (e) => { if (e.type === 'flip') flipEvents = e.count; },
  );
  samples.forEach((s) => tracker.feed(s));

  if (!record) {
    check('throw detected', false, '(no ThrowRecord emitted)');
    continue;
  }
  check('throw detected', true);
  const rec: ThrowRecord = record;
  const result = classifyThrow(rec);

  const expected = Array.isArray(c.expectTrick) ? c.expectTrick : [c.expectTrick];
  check(
    `classified as [${expected.join('|')}]`,
    expected.includes(result.trickId),
    `→ got '${result.trickId}' (${result.trickName}, score ${result.score}, grade ${result.grade})`,
  );

  if (c.expectAirtime) {
    const err = Math.abs(result.features.airtime - c.expectAirtime) / c.expectAirtime;
    check(`airtime within 5% of ${c.expectAirtime}s`, err < 0.05, `→ ${result.features.airtime.toFixed(3)}s (err ${(err * 100).toFixed(1)}%)`);
  }
  if (typeof c.expectCaught === 'boolean') {
    check(`caught == ${c.expectCaught}`, result.features.caught === c.expectCaught, `→ grade ${result.grade}`);
  }
  if (c.minFlips) {
    check(`>= ${c.minFlips} flip FX events`, flipEvents >= c.minFlips, `→ ${flipEvents}`);
  }
  check('trajectory reconstructed', result.trajectory.length > 10, `→ ${result.trajectory.length} points`);
  if (result.trajectory.length > 10) {
    const peak = Math.max(...result.trajectory.map((p) => p.y));
    const expectedPeak = (9.81 * c.params.airtime ** 2) / 8;
    const err = Math.abs(peak - expectedPeak) / expectedPeak;
    check(`peak height ~ ${expectedPeak.toFixed(2)}m`, err < 0.15, `→ ${peak.toFixed(2)}m`);
  }
}

console.log(`\n${'='.repeat(50)}\n${passes} passed, ${failures} failed`);
if (failures > 0) process.exit(1);
