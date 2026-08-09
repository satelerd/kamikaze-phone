import type { Vector3 } from './types';

export type RawRotationRate = {
  alpha: number;
  beta: number;
  gamma: number;
};

/**
 * Expo's DeviceMotion native implementations label rotation-rate axes
 * differently. Normalize every platform to the phone body frame:
 * X = across the screen, Y = along the phone, Z = out of the screen.
 */
export function normalizeRotationRate(
  rotationRate: RawRotationRate | null,
  platform: string,
): Vector3 {
  if (!rotationRate) return { x: 0, y: 0, z: 0 };

  if (platform === 'ios') {
    return {
      x: rotationRate.gamma,
      y: rotationRate.beta,
      z: rotationRate.alpha,
    };
  }

  if (platform === 'web') {
    return {
      x: rotationRate.beta,
      y: rotationRate.gamma,
      z: rotationRate.alpha,
    };
  }

  return {
    x: rotationRate.alpha,
    y: rotationRate.beta,
    z: rotationRate.gamma,
  };
}
