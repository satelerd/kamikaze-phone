import { describe, expect, it } from 'vitest';

import { makeSyntheticThrowSamples, MotionDetector } from './engine';
import { buildReplayFrames, buildTargetFrames, quaternionToEulerDegrees } from './replay';

describe('replay reconstruction', () => {
  it('reconstructs a near-complete X rotation from stored gyro samples', () => {
    const detector = new MotionDetector();
    detector.arm('synthetic');
    let snapshot = detector.process(makeSyntheticThrowSamples()[0]);
    makeSyntheticThrowSamples().slice(1).forEach((sample) => {
      snapshot = detector.process(sample);
    });

    const frames = buildReplayFrames(snapshot.lastAttempt!);
    const finalEuler = quaternionToEulerDegrees(frames.at(-1)!.quaternion);

    expect(frames.length).toBeGreaterThan(80);
    expect(Math.abs(finalEuler.x)).toBeLessThan(25);
    expect(frames.at(-1)!.progress).toBeCloseTo(1, 1);
  });

  it('keeps PHONE FLIP on Y and FRONT FLIP on X in target replays', () => {
    const phoneFlipHalfway = buildTargetFrames('PHONE FLIP')[30].quaternion;
    const frontFlipHalfway = buildTargetFrames('FRONT FLIP')[30].quaternion;

    expect(Math.abs(phoneFlipHalfway.y)).toBeCloseTo(1, 4);
    expect(Math.abs(phoneFlipHalfway.x)).toBeCloseTo(0, 4);
    expect(Math.abs(frontFlipHalfway.x)).toBeCloseTo(1, 4);
    expect(Math.abs(frontFlipHalfway.y)).toBeCloseTo(0, 4);
  });

  it('preserves the opposite X direction for a BACK FLIP target', () => {
    const quarterFrame = buildTargetFrames('BACK FLIP')[15].quaternion;

    expect(quarterFrame.x).toBeLessThan(0);
    expect(Math.abs(quarterFrame.y)).toBeCloseTo(0, 4);
  });
});
