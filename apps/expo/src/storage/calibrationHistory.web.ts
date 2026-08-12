import type { StoredCalibrationCapture } from './calibrationHistory';

const HISTORY_KEY = 'kpf.calibration-history.v1';
const MAX_CAPTURES = 80;

export async function loadCalibrationCaptures(): Promise<StoredCalibrationCapture[]> {
  try {
    const stored = globalThis.localStorage?.getItem(HISTORY_KEY);
    if (!stored) return [];
    const parsed: unknown = JSON.parse(stored);
    return Array.isArray(parsed) ? (parsed as StoredCalibrationCapture[]).slice(0, MAX_CAPTURES) : [];
  } catch {
    return [];
  }
}

export async function appendCalibrationCapture(capture: StoredCalibrationCapture): Promise<void> {
  const existing = await loadCalibrationCaptures();
  globalThis.localStorage?.setItem(
    HISTORY_KEY,
    JSON.stringify([capture, ...existing].slice(0, MAX_CAPTURES)),
  );
}
