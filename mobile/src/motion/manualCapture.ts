import { classifyRotation } from './engine';
import type { DetectedAttempt, MotionSample, RotationSummary, Vector3 } from './types';

const EARTH_GRAVITY = 9.80665;
const magnitude = (vector: Vector3) => Math.hypot(vector.x, vector.y, vector.z);
const zeroRotation = (): RotationSummary => ({ x: 0, y: 0, z: 0, total: 0 });

export function buildManualAttempt(samples: MotionSample[]): DetectedAttempt | null {
  if (samples.length < 2) return null;
  const startS = samples[0].timestampS;
  const endS = samples.at(-1)!.timestampS;
  const biasSamples = samples.filter((sample) => sample.timestampS - startS <= 0.16);
  const bias = biasSamples.reduce((sum, sample) => ({
    x: sum.x + sample.rotationRateDps.x / biasSamples.length,
    y: sum.y + sample.rotationRateDps.y / biasSamples.length,
    z: sum.z + sample.rotationRateDps.z / biasSamples.length,
  }), { x: 0, y: 0, z: 0 });
  const rotation = zeroRotation();
  let peakRotationDps = 0;
  let peakCatchG = 0;
  let previous = samples[0];

  samples.slice(1).forEach((sample) => {
    const dtS = Math.min(0.05, Math.max(0, sample.timestampS - previous.timestampS));
    const average = {
      x: (previous.rotationRateDps.x + sample.rotationRateDps.x) / 2 - bias.x,
      y: (previous.rotationRateDps.y + sample.rotationRateDps.y) / 2 - bias.y,
      z: (previous.rotationRateDps.z + sample.rotationRateDps.z) / 2 - bias.z,
    };
    rotation.x += average.x * dtS;
    rotation.y += average.y * dtS;
    rotation.z += average.z * dtS;
    rotation.total += magnitude(average) * dtS;
    peakRotationDps = Math.max(peakRotationDps, magnitude(average));
    peakCatchG = Math.max(peakCatchG, magnitude(sample.accelerationIncludingGravity) / EARTH_GRAVITY);
    previous = sample;
  });

  const classification = classifyRotation(rotation);
  return {
    airtimeMs: Math.max(0, (endS - startS) * 1000),
    captureMode: 'manual',
    catchTimestampS: endS,
    confidence: classification.confidence,
    estimatedHeightM: 0,
    id: `${Date.now()}-manual-${Math.round(startS * 1000)}`,
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
