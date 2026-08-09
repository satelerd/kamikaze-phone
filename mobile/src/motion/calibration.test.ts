import { describe, expect, it } from 'vitest';

import {
  analyzeCalibrationCapture,
  buildCalibrationReplayFrames,
  type CalibrationStep,
} from './calibration';
import { quaternionToEulerDegrees } from './replay';
import type { MotionSample, Vector3 } from './types';

function samplesFor(rotationRateDps: Vector3, durationS = 1): MotionSample[] {
  return Array.from({ length: 141 }, (_, index) => {
    const timestampS = index * 0.01;
    const moving = timestampS >= 0.35 && timestampS <= 0.35 + durationS;
    return {
      accelerationIncludingGravity: { x: 0, y: 0, z: 9.80665 },
      rotationRateDps: moving ? rotationRateDps : { x: 0, y: 0, z: 0 },
      timestampS,
    };
  });
}

const step: CalibrationStep = {
  axis: 'x',
  degrees: 90,
  direction: 1,
  id: 'x-plus-90-slow',
  tempo: 'slow',
};

describe('calibration analysis', () => {
  it('passes a clean expected-axis rotation', () => {
    const result = analyzeCalibrationCapture(samplesFor({ x: 90, y: 2, z: 1 }), step);

    expect(result.dominantAxis).toBe('x');
    expect(Math.abs(result.measuredDegrees.x - 90)).toBeLessThan(2);
    expect(result.crossTalk).toBeLessThan(0.05);
    expect(result.pass).toBe(true);
  });

  it('exposes a swapped axis instead of silently accepting it', () => {
    const result = analyzeCalibrationCapture(samplesFor({ x: 3, y: -90, z: 1 }), step);

    expect(result.dominantAxis).toBe('y');
    expect(result.directionCorrect).toBe(true);
    expect(result.pass).toBe(false);
  });

  it('reconstructs the captured motion for visual replay', () => {
    const samples = samplesFor({ x: 90, y: 0, z: 0 });
    const frames = buildCalibrationReplayFrames(samples);
    const finalEuler = quaternionToEulerDegrees(frames.at(-1)!.quaternion);

    expect(frames.length).toBe(samples.length);
    expect(Math.abs(finalEuler.x - 90)).toBeLessThan(2);
    expect(frames.at(-1)!.progress).toBe(1);
  });
});
