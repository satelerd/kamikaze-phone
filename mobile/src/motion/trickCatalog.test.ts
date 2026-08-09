import { describe, expect, it } from 'vitest';

import {
  buildDefaultTrickCatalog,
  findBestTrickMatch,
  inferIdealTrickDefinition,
} from './trickCatalog';
import type { DetectedAttempt } from './types';

const attempt = (rotation: { x: number; y: number; z: number }): DetectedAttempt => ({
  airtimeMs: 610,
  catchTimestampS: 0.61,
  confidence: 0.8,
  estimatedHeightM: 0.45,
  id: 'attempt',
  peakCatchG: 1.8,
  peakRotationDps: 720,
  recordedAtIso: new Date(0).toISOString(),
  releaseTimestampS: 0,
  rotationDegrees: { ...rotation, total: Math.abs(rotation.x) + Math.abs(rotation.y) + Math.abs(rotation.z) },
  sampleCount: 3,
  samples: [
    { timestampS: 0, accelerationIncludingGravity: { x: 0, y: 0, z: 9.8 }, rotationRateDps: { x: 0, y: 0, z: 0 } },
    { timestampS: 0.2, accelerationIncludingGravity: { x: 0, y: 0, z: 2 }, rotationRateDps: rotation },
    { timestampS: 0.61, accelerationIncludingGravity: { x: 0, y: 0, z: 9.8 }, rotationRateDps: { x: 0, y: 0, z: 0 } },
  ],
  schemaVersion: 2,
  source: 'sensor',
  trick: 'LEGACY',
});

describe('trick catalog', () => {
  it('uses skate rotation conventions for shuvits and 360 flips', () => {
    const catalog = buildDefaultTrickCatalog('right');
    expect(catalog.find(({ id }) => id === 'bs-shuvit')?.rotation.z).toBe(180);
    expect(catalog.find(({ id }) => id === 'phone-flip')?.rotation).toEqual({ x: 0, y: 360, z: 360 });
  });

  it('distinguishes kickflip and heelflip by direction', () => {
    const catalog = buildDefaultTrickCatalog('right');
    expect(findBestTrickMatch(attempt({ x: 8, y: 356, z: 9 }), catalog).definition.name).toBe('KICKFLIP');
    expect(findBestTrickMatch(attempt({ x: -5, y: -370, z: 4 }), catalog).definition.name).toBe('HEELFLIP');
  });

  it('treats the combined edge flip and full spin as the main Phone Flip', () => {
    const catalog = buildDefaultTrickCatalog('right');
    expect(findBestTrickMatch(attempt({ x: 12, y: 352, z: 371 }), catalog).definition.name).toBe('PHONE FLIP');
    expect(findBestTrickMatch(attempt({ x: -8, y: -365, z: -349 }), catalog).definition.name).toBe('REVERSE PHONE FLIP');
  });

  it('quantizes a recording into an editable mathematical recipe', () => {
    const inferred = inferIdealTrickDefinition('sat flip', attempt({ x: 31, y: 342, z: 171 }));
    expect(inferred.name).toBe('SAT FLIP');
    expect(inferred.rotation).toEqual({ x: 0, y: 360, z: 180 });
    expect(inferred.source).toBe('recording');
  });
});
