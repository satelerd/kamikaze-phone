import type {
  DetectedAttempt,
  Quaternion,
  ReplayFrame,
  Vector3,
} from './types';
import { canonicalizeTrickName } from './tricks';
import type { TrickDefinition } from './trickCatalog';

const EARTH_GRAVITY = 9.80665;
const degreesToRadians = (degrees: number) => degrees * Math.PI / 180;
const radiansToDegrees = (radians: number) => radians * 180 / Math.PI;
const clamp = (value: number, minimum: number, maximum: number) =>
  Math.min(maximum, Math.max(minimum, value));

const vectorMagnitude = (vector: Vector3) =>
  Math.sqrt(vector.x ** 2 + vector.y ** 2 + vector.z ** 2);

export const identityQuaternion = (): Quaternion => ({ w: 1, x: 0, y: 0, z: 0 });

export function multiplyQuaternion(left: Quaternion, right: Quaternion): Quaternion {
  return {
    w: left.w * right.w - left.x * right.x - left.y * right.y - left.z * right.z,
    x: left.w * right.x + left.x * right.w + left.y * right.z - left.z * right.y,
    y: left.w * right.y - left.x * right.z + left.y * right.w + left.z * right.x,
    z: left.w * right.z + left.x * right.y - left.y * right.x + left.z * right.w,
  };
}

export function normalizeQuaternion(quaternion: Quaternion): Quaternion {
  const norm = Math.sqrt(
    quaternion.w ** 2 + quaternion.x ** 2 + quaternion.y ** 2 + quaternion.z ** 2,
  );
  if (norm === 0) return identityQuaternion();
  return {
    w: quaternion.w / norm,
    x: quaternion.x / norm,
    y: quaternion.y / norm,
    z: quaternion.z / norm,
  };
}

export function integrateQuaternion(
  quaternion: Quaternion,
  rotationRateDps: Vector3,
  dtS: number,
): Quaternion {
  const radiansPerSecond = {
    x: degreesToRadians(rotationRateDps.x),
    y: degreesToRadians(rotationRateDps.y),
    z: degreesToRadians(rotationRateDps.z),
  };
  const angularSpeed = vectorMagnitude(radiansPerSecond);
  const angle = angularSpeed * dtS;
  if (angle === 0 || dtS <= 0) return quaternion;

  const halfAngle = angle / 2;
  const scale = Math.sin(halfAngle) / angularSpeed;
  const delta = {
    w: Math.cos(halfAngle),
    x: radiansPerSecond.x * scale,
    y: radiansPerSecond.y * scale,
    z: radiansPerSecond.z * scale,
  };
  return normalizeQuaternion(multiplyQuaternion(quaternion, delta));
}

export function quaternionToEulerDegrees(quaternion: Quaternion): Vector3 {
  const { w, x, y, z } = quaternion;
  const rollX = Math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y));
  const pitchY = Math.asin(clamp(2 * (w * y - z * x), -1, 1));
  const yawZ = Math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z));
  return {
    x: radiansToDegrees(rollX),
    y: radiansToDegrees(pitchY),
    z: radiansToDegrees(yawZ),
  };
}

export function quaternionFromEulerDegrees(euler: Vector3): Quaternion {
  const x = degreesToRadians(euler.x) / 2;
  const y = degreesToRadians(euler.y) / 2;
  const z = degreesToRadians(euler.z) / 2;
  const cx = Math.cos(x);
  const sx = Math.sin(x);
  const cy = Math.cos(y);
  const sy = Math.sin(y);
  const cz = Math.cos(z);
  const sz = Math.sin(z);
  return normalizeQuaternion({
    w: cx * cy * cz + sx * sy * sz,
    x: sx * cy * cz - cx * sy * sz,
    y: cx * sy * cz + sx * cy * sz,
    z: cx * cy * sz - sx * sy * cz,
  });
}

export function buildReplayFrames(attempt: DetectedAttempt): ReplayFrame[] {
  const postRollS = 0.22;
  const flightSamples = attempt.samples.filter((sample) =>
    sample.timestampS >= attempt.releaseTimestampS &&
    sample.timestampS <= attempt.catchTimestampS + postRollS,
  );
  if (flightSamples.length === 0) return [];

  let quaternion = identityQuaternion();
  let previous = flightSamples[0];
  return flightSamples.map((sample, index) => {
    if (index > 0) {
      const dtS = clamp(sample.timestampS - previous.timestampS, 0, 0.05);
      const averageRate = {
        x: (previous.rotationRateDps.x + sample.rotationRateDps.x) / 2,
        y: (previous.rotationRateDps.y + sample.rotationRateDps.y) / 2,
        z: (previous.rotationRateDps.z + sample.rotationRateDps.z) / 2,
      };
      quaternion = integrateQuaternion(quaternion, averageRate, dtS);
    }
    previous = sample;

    const progress = attempt.airtimeMs <= 0
      ? 0
      : clamp((sample.timestampS - attempt.releaseTimestampS) * 1000 / attempt.airtimeMs, 0, 1);
    return {
      timestampMs: (sample.timestampS - attempt.releaseTimestampS) * 1000,
      progress,
      quaternion: { ...quaternion },
      accelG: vectorMagnitude(sample.accelerationIncludingGravity) / EARTH_GRAVITY,
      gyroDps: vectorMagnitude(sample.rotationRateDps),
    };
  });
}

export function buildTargetFrames(
  trick: string | TrickDefinition,
  frameCount = 61,
): ReplayFrame[] {
  const normalized = canonicalizeTrickName(typeof trick === 'string' ? trick : trick.name).toUpperCase();
  const targetRotation = typeof trick !== 'string'
    ? trick.rotation
    : normalized.includes('TRE') || normalized.includes('360 FLIP')
    ? { x: 0, y: 360, z: 360 }
    : normalized.includes('SHUVIT −') || normalized.includes('FRONTSIDE SHUVIT')
      ? { x: 0, y: 0, z: -180 }
      : normalized.includes('SHUVIT')
        ? { x: 0, y: 0, z: 180 }
        : normalized.includes('HEELFLIP') || normalized.includes('FLIP −')
          ? { x: 0, y: -360, z: 0 }
      : normalized.startsWith('PHONE FLIP') || normalized.includes('KAMIKAZE')
        ? { x: 360, y: 0, z: 0 }
        : normalized.startsWith('FLIP') || normalized.includes('KICKFLIP')
          ? { x: 0, y: 360, z: 0 }
          : { x: 360, y: 0, z: 0 };

  const durationMs = typeof trick === 'string' ? 900 : trick.durationMs;

  return Array.from({ length: frameCount }, (_, index) => {
    const progress = index / (frameCount - 1);
    return {
      timestampMs: progress * durationMs,
      progress,
      quaternion: quaternionFromEulerDegrees({
        x: targetRotation.x * progress,
        y: targetRotation.y * progress,
        z: targetRotation.z * progress,
      }),
      accelG: progress > 0 && progress < 1 ? 0 : 1,
      gyroDps: vectorMagnitude(targetRotation) / (durationMs / 1000),
    };
  });
}
