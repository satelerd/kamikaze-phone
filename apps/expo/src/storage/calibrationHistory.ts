import Storage from 'expo-sqlite/kv-store';

import type { CalibrationResult, CalibrationStep } from '../motion/calibration';
import type { MotionSample } from '../motion/types';

export type StoredCalibrationCapture = {
  id: string;
  recordedAtIso: string;
  result: CalibrationResult;
  samples: MotionSample[];
  step: CalibrationStep;
};

const HISTORY_KEY = 'kpf.calibration-history.v1';
const MAX_CAPTURES = 80;

export async function loadCalibrationCaptures(): Promise<StoredCalibrationCapture[]> {
  try {
    const stored = await Storage.getItem(HISTORY_KEY);
    if (!stored) return [];
    const parsed: unknown = JSON.parse(stored);
    return Array.isArray(parsed) ? (parsed as StoredCalibrationCapture[]).slice(0, MAX_CAPTURES) : [];
  } catch {
    return [];
  }
}

export async function appendCalibrationCapture(capture: StoredCalibrationCapture): Promise<void> {
  const existing = await loadCalibrationCaptures();
  await Storage.setItem(HISTORY_KEY, JSON.stringify([capture, ...existing].slice(0, MAX_CAPTURES)));
}
