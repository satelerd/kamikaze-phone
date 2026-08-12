import type { StoredTrickCalibration } from './trickCalibrationHistory';

const KEY = 'kpf.trick-calibration-history.v1';
const MAX = 80;

export async function loadTrickCalibrations(): Promise<StoredTrickCalibration[]> {
  try {
    const stored = globalThis.localStorage?.getItem(KEY);
    if (!stored) return [];
    const parsed: unknown = JSON.parse(stored);
    return Array.isArray(parsed) ? (parsed as StoredTrickCalibration[]).slice(0, MAX) : [];
  } catch {
    return [];
  }
}

export async function appendTrickCalibration(capture: StoredTrickCalibration): Promise<void> {
  const existing = await loadTrickCalibrations();
  globalThis.localStorage?.setItem(KEY, JSON.stringify([capture, ...existing].slice(0, MAX)));
}
