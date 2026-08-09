import { describe, expect, it } from 'vitest';

import { buildManualAttempt } from './manualCapture';
import type { MotionSample } from './types';

describe('manual trick capture', () => {
  it('classifies a low, manually bounded shuvit without freefall', () => {
    const samples: MotionSample[] = Array.from({ length: 101 }, (_, index) => ({
      accelerationIncludingGravity: { x: 0, y: 0, z: 9.80665 },
      rotationRateDps: index >= 20 && index <= 70
        ? { x: 0, y: 4, z: 450 }
        : { x: 0, y: 0, z: 0 },
      timestampS: 10 + index * 0.01,
    }));
    const attempt = buildManualAttempt(samples)!;

    expect(attempt.captureMode).toBe('manual');
    expect(attempt.trick).toContain('SHUVIT');
    expect(attempt.samples).toHaveLength(samples.length);
    expect(attempt.airtimeMs).toBeCloseTo(500, 0);
  });

  it('selects the main phone-flip burst instead of manual pre-roll and catch noise', () => {
    const samples: MotionSample[] = Array.from({ length: 131 }, (_, index) => {
      const inFlip = index >= 30 && index <= 80;
      const catchSpike = index === 95;
      return {
        accelerationIncludingGravity: { x: 0, y: 0, z: catchSpike ? 35 : 9.80665 },
        rotationRateDps: inFlip
          ? { x: Math.sin(index) * 120, y: 720, z: Math.cos(index) * 90 }
          : catchSpike ? { x: 900, y: 0, z: 0 } : { x: 0, y: 0, z: 0 },
        timestampS: 20 + index * 0.01,
      };
    });
    const attempt = buildManualAttempt(samples)!;

    expect(attempt.trick).toBe('PHONE FLIP');
    expect(attempt.airtimeMs).toBeCloseTo(500, 0);
    expect(attempt.rotationDegrees.y).toBeGreaterThan(340);
    expect(Math.abs(attempt.rotationDegrees.x)).toBeLessThan(20);
  });
});
