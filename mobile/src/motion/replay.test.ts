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

  it('keeps FLIP on Y and PHONE FLIP on X in target replays', () => {
    const flipHalfway = buildTargetFrames('FLIP +')[30].quaternion;
    const phoneFlipHalfway = buildTargetFrames('PHONE FLIP +')[30].quaternion;

    expect(Math.abs(flipHalfway.y)).toBeCloseTo(1, 4);
    expect(Math.abs(flipHalfway.x)).toBeCloseTo(0, 4);
    expect(Math.abs(phoneFlipHalfway.x)).toBeCloseTo(1, 4);
    expect(Math.abs(phoneFlipHalfway.y)).toBeCloseTo(0, 4);
  });
});
