import { describe, expect, it } from 'vitest';

import { buildManualAttempt } from './manualCapture';
import type { MotionSample } from './types';

describe('manual trick capture', () => {
  it('classifies a low, manually bounded shuvit without freefall', () => {
    const samples: MotionSample[] = Array.from({ length: 101 }, (_, index) => ({
      accelerationIncludingGravity: { x: 0, y: 0, z: 9.80665 },
      rotationRateDps: index < 20 ? { x: 0, y: 0, z: 0 } : { x: 0, y: 4, z: 450 },
      timestampS: 10 + index * 0.01,
    }));
    const attempt = buildManualAttempt(samples)!;

    expect(attempt.captureMode).toBe('manual');
    expect(attempt.trick).toContain('SHUVIT');
    expect(attempt.samples).toHaveLength(samples.length);
    expect(attempt.airtimeMs).toBeCloseTo(1000, 0);
  });
});
