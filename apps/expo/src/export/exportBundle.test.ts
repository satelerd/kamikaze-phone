import { describe, expect, it } from 'vitest';

import {
  buildExportBundle,
  EXPORT_BUNDLE_FORMAT,
  isKamikazeExportBundleV2,
} from './exportBundle';

describe('Expo export bundle', () => {
  it('round-trips a versioned snapshot without mutating its evidence', () => {
    const bundle = buildExportBundle({
      attempts: [],
      calibrationCaptures: [],
      customTricks: [],
      settings: {
        cameraPreset: null,
        gamePreferences: {
          onboardingComplete: false,
          selectedSkinId: 'ion',
          showPerformanceHud: false,
        },
        gripHand: 'right',
        motionCalibrationProfile: null,
      },
      trickCalibrations: [],
    }, {
      app: 'Kamikaze: Phone Flip',
      appVersion: '0.3.0',
      deviceModel: 'iPhone 15 Plus',
      osVersion: '26.5',
      platform: 'ios',
      runtime: 'expo',
    }, '2026-08-12T12:00:00.000Z');

    const parsed: unknown = JSON.parse(JSON.stringify(bundle));

    expect(bundle.format).toBe(EXPORT_BUNDLE_FORMAT);
    expect(bundle.bundleSchemaVersion).toBe(2);
    expect(bundle.settings.gripHand).toBe('right');
    expect(isKamikazeExportBundleV2(parsed)).toBe(true);
  });

  it('rejects an unversioned JSON object', () => {
    expect(isKamikazeExportBundleV2({ attempts: [] })).toBe(false);
  });
});
