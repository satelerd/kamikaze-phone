import { describe, expect, it } from 'vitest';

import { makeSyntheticThrowSamples, MotionDetector } from './engine';
import type { MotionSample } from './types';

function run(samples: MotionSample[]) {
  const detector = new MotionDetector();
  detector.arm();
  let snapshot = detector.process(samples[0]);
  samples.slice(1).forEach((sample) => {
    snapshot = detector.process(sample);
  });
  return snapshot;
}

describe('MotionDetector', () => {
  it('detects a caught phone flip from a 100 Hz flight window', () => {
    const snapshot = run(makeSyntheticThrowSamples());

    expect(snapshot.phase).toBe('complete');
    expect(snapshot.lastAttempt?.trick).toContain('PHONE FLIP');
    expect(snapshot.lastAttempt?.airtimeMs).toBeCloseTo(920, -1);
    expect(snapshot.lastAttempt?.estimatedHeightM).toBeCloseTo(1.04, 1);
    expect(snapshot.lastAttempt?.rotationDegrees.x).toBeGreaterThan(300);
  });

  it('recognizes a combined long-axis roll and screen-normal spin', () => {
    const snapshot = run(makeSyntheticThrowSamples({
      airtimeMs: 1050,
      rotationDps: { x: 20, y: 390, z: 260 },
    }));

    expect(snapshot.phase).toBe('complete');
    expect(snapshot.lastAttempt?.trick).toBe('TRE COMBO');
  });

  it('keeps a straight throw separate from a flip', () => {
    const snapshot = run(makeSyntheticThrowSamples({
      rotationDps: { x: 12, y: 8, z: 5 },
    }));

    expect(snapshot.lastAttempt?.trick).toBe('STRAIGHT AIR');
  });

  it('names a dominant long-edge rotation FLIP', () => {
    const snapshot = run(makeSyntheticThrowSamples({
      airtimeMs: 420,
      rotationDps: { x: 8, y: 900, z: 12 },
    }));

    expect(snapshot.lastAttempt?.trick).toBe('FLIP +');
    expect(snapshot.lastAttempt?.rotationDegrees.y).toBeGreaterThan(330);
  });

  it('rejects low-g glitches shorter than the release threshold', () => {
    const detector = new MotionDetector();
    detector.arm();
    let timestampS = 50;
    let snapshot = detector.process({
      timestampS,
      accelerationIncludingGravity: { x: 0, y: 0, z: 9.80665 },
      rotationRateDps: { x: 0, y: 0, z: 0 },
    });

    for (let index = 0; index < 2; index += 1) {
      timestampS += 0.01;
      snapshot = detector.process({
        timestampS,
        accelerationIncludingGravity: { x: 0, y: 0, z: 0.2 },
        rotationRateDps: { x: 0, y: 0, z: 0 },
      });
    }

    timestampS += 0.01;
    snapshot = detector.process({
      timestampS,
      accelerationIncludingGravity: { x: 0, y: 0, z: 9.80665 },
      rotationRateDps: { x: 0, y: 0, z: 0 },
    });

    expect(snapshot.phase).toBe('armed');
  });

  it('captures a fast low phone flip without losing the first rotation samples', () => {
    const snapshot = run(makeSyntheticThrowSamples({
      airtimeMs: 190,
      rotationDps: { x: 1900, y: 20, z: 10 },
    }));

    expect(snapshot.phase).toBe('complete');
    expect(snapshot.lastAttempt?.trick).toContain('PHONE FLIP');
    expect(snapshot.lastAttempt?.rotationDegrees.x).toBeGreaterThan(330);
    expect(snapshot.lastAttempt?.samples.length).toBeGreaterThan(40);
  });

  it('keeps pre-release sensor samples for later calibration and replay', () => {
    const snapshot = run(makeSyntheticThrowSamples({ airtimeMs: 300 }));
    const attempt = snapshot.lastAttempt!;

    expect(attempt.samples[0].timestampS).toBeLessThan(attempt.releaseTimestampS);
    expect(attempt.samples.at(-1)!.timestampS).toBeGreaterThan(attempt.catchTimestampS);
  });

  it('detects a low shuvit from gyro motion without requiring freefall', () => {
    const samples: MotionSample[] = [];
    let timestampS = 80;
    const push = (count: number, rotationRateDps: MotionSample['rotationRateDps']) => {
      for (let index = 0; index < count; index += 1) {
        samples.push({
          accelerationIncludingGravity: { x: 0, y: 0, z: 9.80665 },
          rotationRateDps,
          timestampS,
        });
        timestampS += 0.01;
      }
    };
    push(25, { x: 0, y: 0, z: 0 });
    push(85, { x: 5, y: 3, z: 450 });
    push(55, { x: 0, y: 0, z: 0 });
    const snapshot = run(samples);

    expect(snapshot.phase).toBe('complete');
    expect(snapshot.lastAttempt?.triggerMode).toBe('gyro');
    expect(snapshot.lastAttempt?.trick).toContain('SHUVIT');
    expect(snapshot.lastAttempt?.estimatedHeightM).toBe(0);
  });
});
