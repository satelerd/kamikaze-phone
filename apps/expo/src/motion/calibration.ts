import { integrateQuaternion } from './replay';
import type { MotionSample, ReplayFrame, Vector3 } from './types';

export type MotionAxis = 'x' | 'y' | 'z';
export type CalibrationTempo = 'slow' | 'fast';

export type CalibrationStep = {
  axis: MotionAxis;
  degrees: 90 | 360;
  direction: 1 | -1;
  id: string;
  tempo: CalibrationTempo;
};

export type CalibrationResult = {
  biasDps: Vector3;
  crossTalk: number;
  directionCorrect: boolean;
  dominantAxis: MotionAxis;
  expectedAxis: MotionAxis;
  expectedDegrees: number;
  gain: number;
  measuredDegrees: Vector3;
  pass: boolean;
  sampleCount: number;
  score: number;
  stepId: string;
};

export type AxisCalibration = {
  confidence: number;
  gain: number;
  logicalAxis: MotionAxis;
  rawAxis: MotionAxis;
  sign: 1 | -1;
};

export function applyAxisCalibration(
  raw: Vector3,
  profile: AxisCalibration[] | null,
): Vector3 {
  if (!profile || profile.length !== 3) return { ...raw };
  const corrected: Vector3 = { x: 0, y: 0, z: 0 };
  profile.forEach(({ gain, logicalAxis, rawAxis, sign }) => {
    corrected[logicalAxis] = raw[rawAxis] * sign * gain;
  });
  return corrected;
}

export const CALIBRATION_STEPS: CalibrationStep[] = (['x', 'y', 'z'] as MotionAxis[])
  .flatMap((axis) => ([
    { axis, degrees: 90, direction: 1, tempo: 'slow' },
    { axis, degrees: 90, direction: -1, tempo: 'slow' },
    { axis, degrees: 360, direction: 1, tempo: 'fast' },
    { axis, degrees: 360, direction: -1, tempo: 'fast' },
  ] as const).map((step) => ({
    ...step,
    id: `${axis}-${step.direction > 0 ? 'plus' : 'minus'}-${step.degrees}-${step.tempo}`,
  })));

const axes: MotionAxis[] = ['x', 'y', 'z'];
const magnitude = (vector: Vector3) => Math.hypot(vector.x, vector.y, vector.z);
const clamp = (value: number, minimum: number, maximum: number) =>
  Math.min(maximum, Math.max(minimum, value));

function meanRotationRate(samples: MotionSample[]): Vector3 {
  if (samples.length === 0) return { x: 0, y: 0, z: 0 };
  const sum = samples.reduce((total, sample) => ({
    x: total.x + sample.rotationRateDps.x,
    y: total.y + sample.rotationRateDps.y,
    z: total.z + sample.rotationRateDps.z,
  }), { x: 0, y: 0, z: 0 });
  return {
    x: sum.x / samples.length,
    y: sum.y / samples.length,
    z: sum.z / samples.length,
  };
}

export function analyzeCalibrationCapture(
  samples: MotionSample[],
  step: CalibrationStep,
): CalibrationResult {
  if (samples.length < 2) {
    return {
      biasDps: { x: 0, y: 0, z: 0 },
      crossTalk: 1,
      directionCorrect: false,
      dominantAxis: 'x',
      expectedAxis: step.axis,
      expectedDegrees: step.degrees * step.direction,
      gain: 1,
      measuredDegrees: { x: 0, y: 0, z: 0 },
      pass: false,
      sampleCount: samples.length,
      score: 0,
      stepId: step.id,
    };
  }

  const captureStart = samples[0].timestampS;
  const biasSamples = samples.filter((sample) => sample.timestampS - captureStart <= 0.32);
  const biasDps = meanRotationRate(biasSamples);
  const measuredDegrees: Vector3 = { x: 0, y: 0, z: 0 };

  let previous = samples[0];
  for (const sample of samples.slice(1)) {
    const dtS = clamp(sample.timestampS - previous.timestampS, 0, 0.05);
    const previousCorrected = {
      x: previous.rotationRateDps.x - biasDps.x,
      y: previous.rotationRateDps.y - biasDps.y,
      z: previous.rotationRateDps.z - biasDps.z,
    };
    const currentCorrected = {
      x: sample.rotationRateDps.x - biasDps.x,
      y: sample.rotationRateDps.y - biasDps.y,
      z: sample.rotationRateDps.z - biasDps.z,
    };
    if (Math.max(magnitude(previousCorrected), magnitude(currentCorrected)) >= 7) {
      axes.forEach((axis) => {
        measuredDegrees[axis] += (previousCorrected[axis] + currentCorrected[axis]) * 0.5 * dtS;
      });
    }
    previous = sample;
  }

  const dominantAxis = axes.reduce((best, axis) =>
    Math.abs(measuredDegrees[axis]) > Math.abs(measuredDegrees[best]) ? axis : best, 'x');
  const totalAxisEnergy = axes.reduce((sum, axis) => sum + Math.abs(measuredDegrees[axis]), 0);
  const expectedMeasured = measuredDegrees[step.axis];
  const dominance = totalAxisEnergy === 0 ? 0 : Math.abs(expectedMeasured) / totalAxisEnergy;
  const crossTalk = 1 - dominance;
  const directionCorrect = Math.sign(expectedMeasured) === step.direction;
  const degreeAccuracy = clamp(1 - Math.abs(Math.abs(expectedMeasured) - step.degrees) / step.degrees, 0, 1);
  const score = clamp(dominance * 0.55 + degreeAccuracy * 0.3 + (directionCorrect ? 0.15 : 0), 0, 1);
  const gain = Math.abs(expectedMeasured) < 1 ? 1 : step.degrees / Math.abs(expectedMeasured);
  const tolerance = Math.max(24, step.degrees * 0.34);
  const pass = dominantAxis === step.axis &&
    directionCorrect &&
    Math.abs(Math.abs(expectedMeasured) - step.degrees) <= tolerance &&
    crossTalk <= 0.32;

  return {
    biasDps,
    crossTalk,
    directionCorrect,
    dominantAxis,
    expectedAxis: step.axis,
    expectedDegrees: step.degrees * step.direction,
    gain,
    measuredDegrees,
    pass,
    sampleCount: samples.length,
    score,
    stepId: step.id,
  };
}

export function buildCalibrationReplayFrames(
  samples: MotionSample[],
  biasDps?: Vector3,
): ReplayFrame[] {
  if (samples.length === 0) return [];
  const captureStart = samples[0].timestampS;
  const measuredBias = biasDps ?? meanRotationRate(
    samples.filter((sample) => sample.timestampS - captureStart <= 0.32),
  );
  const durationS = Math.max(samples.at(-1)!.timestampS - captureStart, 0.001);
  let quaternion = { w: 1, x: 0, y: 0, z: 0 };
  let previous = samples[0];

  return samples.map((sample, index) => {
    const corrected = {
      x: sample.rotationRateDps.x - measuredBias.x,
      y: sample.rotationRateDps.y - measuredBias.y,
      z: sample.rotationRateDps.z - measuredBias.z,
    };
    if (index > 0) {
      const previousCorrected = {
        x: previous.rotationRateDps.x - measuredBias.x,
        y: previous.rotationRateDps.y - measuredBias.y,
        z: previous.rotationRateDps.z - measuredBias.z,
      };
      const average = {
        x: (previousCorrected.x + corrected.x) / 2,
        y: (previousCorrected.y + corrected.y) / 2,
        z: (previousCorrected.z + corrected.z) / 2,
      };
      quaternion = integrateQuaternion(
        quaternion,
        magnitude(average) >= 7 ? average : { x: 0, y: 0, z: 0 },
        clamp(sample.timestampS - previous.timestampS, 0, 0.05),
      );
    }
    previous = sample;
    return {
      accelG: magnitude(sample.accelerationIncludingGravity) / 9.80665,
      gyroDps: magnitude(corrected),
      progress: clamp((sample.timestampS - captureStart) / durationS, 0, 1),
      quaternion: { ...quaternion },
      timestampMs: (sample.timestampS - captureStart) * 1000,
    };
  });
}

const median = (values: number[]): number => {
  if (values.length === 0) return 1;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[middle - 1] + sorted[middle]) / 2
    : sorted[middle];
};

export function summarizeCalibration(
  results: CalibrationResult[],
  steps: CalibrationStep[] = CALIBRATION_STEPS,
): AxisCalibration[] {
  return axes.map((logicalAxis) => {
    const axisResults = results.filter((result) => result.expectedAxis === logicalAxis);
    const axisVotes = axes.map((rawAxis) => ({
      rawAxis,
      votes: axisResults.filter((result) => result.dominantAxis === rawAxis).length,
    }));
    const winner = axisVotes.reduce((best, vote) => vote.votes > best.votes ? vote : best);
    const matching = axisResults.filter((result) => result.dominantAxis === winner.rawAxis);
    const signVotes = matching.map((result) => {
      const step = steps.find(({ id }) => id === result.stepId);
      const rawSign = Math.sign(result.measuredDegrees[winner.rawAxis]) || 1;
      return step ? rawSign * step.direction : 1;
    });
    const positiveVotes = signVotes.filter((sign) => sign > 0).length;
    return {
      confidence: axisResults.length === 0 ? 0 : winner.votes / axisResults.length,
      gain: median(matching.map((result) => result.gain)),
      logicalAxis,
      rawAxis: winner.rawAxis,
      sign: positiveVotes >= signVotes.length / 2 ? 1 : -1,
    };
  });
}
