import type { OrbitCamera } from '../components/PhoneScene3D';
import type { AxisCalibration } from '../motion/calibration';
import type { DetectedAttempt } from '../motion/types';
import type { GripHand, TrickDefinition } from '../motion/trickCatalog';
import type { StoredCalibrationCapture } from '../storage/calibrationHistory';
import type { StoredTrickCalibration } from '../storage/trickCalibrationHistory';
import type { GamePreferences } from '../game/gameProfile';

export const EXPORT_BUNDLE_FORMAT = 'kpf-export-bundle' as const;
export const EXPORT_BUNDLE_SCHEMA_VERSION = 2 as const;

export type ExportProducer = {
  app: 'Kamikaze: Phone Flip';
  appVersion: string;
  deviceModel: string;
  osVersion: string;
  platform: string;
  runtime: 'expo';
};

export type ExportSettings = {
  cameraPreset: OrbitCamera | null;
  gamePreferences: GamePreferences;
  gripHand: GripHand;
  motionCalibrationProfile: AxisCalibration[] | null;
};

export type ExportSnapshot = {
  attempts: DetectedAttempt[];
  calibrationCaptures: StoredCalibrationCapture[];
  customTricks: TrickDefinition[];
  settings: ExportSettings;
  trickCalibrations: StoredTrickCalibration[];
};

export type KamikazeExportBundleV2 = ExportSnapshot & {
  bundleSchemaVersion: typeof EXPORT_BUNDLE_SCHEMA_VERSION;
  exportedAtIso: string;
  format: typeof EXPORT_BUNDLE_FORMAT;
  producer: ExportProducer;
  vocabularyVersion: 1;
};

export function buildExportBundle(
  snapshot: ExportSnapshot,
  producer: ExportProducer,
  exportedAtIso = new Date().toISOString(),
): KamikazeExportBundleV2 {
  return {
    format: EXPORT_BUNDLE_FORMAT,
    bundleSchemaVersion: EXPORT_BUNDLE_SCHEMA_VERSION,
    exportedAtIso,
    producer,
    vocabularyVersion: 1,
    ...snapshot,
  };
}
export function isKamikazeExportBundleV2(value: unknown): value is KamikazeExportBundleV2 {
  if (!value || typeof value !== 'object') return false;
  const bundle = value as Partial<KamikazeExportBundleV2>;
  return bundle.format === EXPORT_BUNDLE_FORMAT &&
    bundle.bundleSchemaVersion === EXPORT_BUNDLE_SCHEMA_VERSION &&
    typeof bundle.exportedAtIso === 'string' &&
    Array.isArray(bundle.attempts) &&
    Array.isArray(bundle.calibrationCaptures) &&
    Array.isArray(bundle.trickCalibrations) &&
    Array.isArray(bundle.customTricks) &&
    Boolean(bundle.settings) &&
    Boolean(bundle.producer);
}
