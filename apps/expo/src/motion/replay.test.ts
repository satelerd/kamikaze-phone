import { describe, expect, it } from 'vitest';

import { makeSyntheticThrowSamples, MotionDetector } from './engine';
import {
  buildReplayFrames,
  buildTargetFrames,
  normalizeReplayFrames,
  quaternionToEulerDegrees,
  sampleReplayFrame,
} from './replay';

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

  it('normalizes captured pre-roll and samples the replay by elapsed time', () => {
    const target = buildTargetFrames('FRONT FLIP', 3).map((frame) => ({
      ...frame,
      timestampMs: frame.timestampMs - 120,
    }));
    const frames = normalizeReplayFrames(target);
    const halfway = sampleReplayFrame(frames, frames.at(-1)!.timestampMs / 2);

    expect(frames[0].timestampMs).toBe(0);
    expect(frames.at(-1)!.progress).toBe(1);
    expect(Math.abs(halfway.quaternion.x)).toBeCloseTo(1, 4);
    expect(halfway.progress).toBeCloseTo(0.5, 4);
  });

  it('interpolates irregular samples instead of jumping by array index', () => {
    const frames = normalizeReplayFrames(buildTargetFrames('PHONE FLIP', 3));
    const firstQuarter = sampleReplayFrame(frames, frames.at(-1)!.timestampMs / 4);

    expect(Math.abs(firstQuarter.quaternion.y)).toBeCloseTo(Math.SQRT1_2, 4);
    expect(firstQuarter.progress).toBeCloseTo(0.25, 4);
  });
});
