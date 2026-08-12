import { describe, expect, it } from 'vitest';

import { normalizeRotationRate } from './normalize';

const raw = { alpha: 10, beta: 20, gamma: 30 };

describe('normalizeRotationRate', () => {
  it('maps Expo iOS CoreMotion labels back to body-frame XYZ', () => {
    expect(normalizeRotationRate(raw, 'ios')).toEqual({ x: 30, y: 20, z: 10 });
  });

  it('keeps Android sensor XYZ order', () => {
    expect(normalizeRotationRate(raw, 'android')).toEqual({ x: 10, y: 20, z: 30 });
  });

  it('maps the W3C DeviceMotion rotation convention on web', () => {
    expect(normalizeRotationRate(raw, 'web')).toEqual({ x: 20, y: 30, z: 10 });
  });
});
