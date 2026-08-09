import { classifyRotation } from './engine';
import type { DetectedAttempt, MotionSample, RotationSummary, Vector3 } from './types';

const EARTH_GRAVITY = 9.80665;
const magnitude = (vector: Vector3) => Math.hypot(vector.x, vector.y, vector.z);
const zeroRotation = (): RotationSummary => ({ x: 0, y: 0, z: 0, total: 0 });
const axes = ['x', 'y', 'z'] as const;

type MotionWindow = {
  endIndex: number;
  startIndex: number;
};

function estimateBias(samples: MotionSample[]): Vector3 {
  const startS = samples[0].timestampS;
  const candidates = samples
    .filter((sample) => sample.timestampS - startS <= 0.45)
    .sort((left, right) => magnitude(left.rotationRateDps) - magnitude(right.rotationRateDps));
  const quietCount = Math.min(12, Math.max(5, Math.ceil(candidates.length * 0.2)));
  const quietest = candidates.slice(0, quietCount);
  if (quietest.length === 0 || magnitude(quietest[0].rotationRateDps) > 100) {
    return { x: 0, y: 0, z: 0 };
  }
  return quietest.reduce((bias, sample) => ({
    x: bias.x + sample.rotationRateDps.x / quietest.length,
    y: bias.y + sample.rotationRateDps.y / quietest.length,
    z: bias.z + sample.rotationRateDps.z / quietest.length,
  }), { x: 0, y: 0, z: 0 });
}

function adjustedRates(samples: MotionSample[], bias: Vector3): Vector3[] {
  return samples.map((sample) => ({
    x: sample.rotationRateDps.x - bias.x,
    y: sample.rotationRateDps.y - bias.y,
    z: sample.rotationRateDps.z - bias.z,
  }));
}

function angularPath(
  samples: MotionSample[],
  rates: Vector3[],
  startIndex: number,
  endIndex: number,
): number {
  let path = 0;
  for (let index = startIndex + 1; index <= endIndex; index += 1) {
    const dtS = Math.min(0.05, Math.max(0, samples[index].timestampS - samples[index - 1].timestampS));
    path += magnitude({
      x: (rates[index - 1].x + rates[index].x) / 2,
      y: (rates[index - 1].y + rates[index].y) / 2,
      z: (rates[index - 1].z + rates[index].z) / 2,
    }) * dtS;
  }
  return path;
}

function findPrimaryMotionWindow(samples: MotionSample[], bias: Vector3): MotionWindow {
  const rates = adjustedRates(samples, bias);
  const speeds = rates.map(magnitude);
  const peakDps = Math.max(...speeds);
  const enterDps = Math.max(160, peakDps * 0.16);
  const rawSegments: MotionWindow[] = [];
  let startIndex: number | null = null;

  speeds.forEach((speed, index) => {
    if (speed >= enterDps && startIndex === null) startIndex = index;
    if (speed < enterDps && startIndex !== null) {
      rawSegments.push({ startIndex, endIndex: index - 1 });
      startIndex = null;
    }
  });
  if (startIndex !== null) rawSegments.push({ startIndex, endIndex: samples.length - 1 });

  const merged = rawSegments.reduce<MotionWindow[]>((segments, segment) => {
    const previous = segments.at(-1);
    if (
      previous &&
      samples[segment.startIndex].timestampS - samples[previous.endIndex].timestampS <= 0.1
    ) {
      previous.endIndex = segment.endIndex;
    } else {
      segments.push({ ...segment });
    }
    return segments;
  }, []);

  return merged.sort((left, right) =>
    angularPath(samples, rates, right.startIndex, right.endIndex) -
    angularPath(samples, rates, left.startIndex, left.endIndex),
  )[0] ?? { startIndex: 0, endIndex: samples.length - 1 };
}

export function buildManualAttempt(samples: MotionSample[]): DetectedAttempt | null {
  if (samples.length < 2) return null;
  const bias = estimateBias(samples);
  const rates = adjustedRates(samples, bias);
  const { startIndex, endIndex } = findPrimaryMotionWindow(samples, bias);
  const startS = samples[startIndex].timestampS;
  const endS = samples[endIndex].timestampS;
  const rotation = zeroRotation();
  let peakRotationDps = 0;
  let peakCatchG = 0;

  for (let index = startIndex + 1; index <= endIndex; index += 1) {
    const sample = samples[index];
    const previous = samples[index - 1];
    const previousRate = rates[index - 1];
    const rate = rates[index];
    const dtS = Math.min(0.05, Math.max(0, sample.timestampS - previous.timestampS));
    const average = {
      x: (previousRate.x + rate.x) / 2,
      y: (previousRate.y + rate.y) / 2,
      z: (previousRate.z + rate.z) / 2,
    };
    axes.forEach((axis) => { rotation[axis] += average[axis] * dtS; });
    rotation.total += magnitude(average) * dtS;
    peakRotationDps = Math.max(peakRotationDps, magnitude(average));
  }

  const catchWindowEndS = endS + 0.22;
  samples.slice(endIndex).forEach((sample) => {
    if (sample.timestampS > catchWindowEndS) return;
    peakCatchG = Math.max(peakCatchG, magnitude(sample.accelerationIncludingGravity) / EARTH_GRAVITY);
  });

  const classification = classifyRotation(rotation);
  return {
    airtimeMs: Math.max(0, (endS - startS) * 1000),
    captureMode: 'manual',
    catchTimestampS: endS,
    confidence: classification.confidence,
    estimatedHeightM: 0,
    id: `${Date.now()}-manual-${Math.round(samples[0].timestampS * 1000)}`,
    peakCatchG,
    peakRotationDps,
    recordedAtIso: new Date().toISOString(),
    releaseTimestampS: startS,
    rotationDegrees: rotation,
    sampleCount: samples.length,
    samples: samples.map((sample) => ({
      ...sample,
      accelerationIncludingGravity: { ...sample.accelerationIncludingGravity },
      rotationRateDps: { ...sample.rotationRateDps },
    })),
    schemaVersion: 2,
    source: 'sensor',
    trick: classification.trick,
  };
}
