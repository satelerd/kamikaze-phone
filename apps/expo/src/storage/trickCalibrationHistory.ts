import Storage from 'expo-sqlite/kv-store';

import type { DetectedAttempt } from '../motion/types';

export type StoredTrickCalibration = {
  attempt: DetectedAttempt;
  expectedTrick: string;
  id: string;
  recordedAtIso: string;
};

const KEY = 'kpf.trick-calibration-history.v1';
const MAX = 80;

export async function loadTrickCalibrations(): Promise<StoredTrickCalibration[]> {
  try {
    const stored = await Storage.getItem(KEY);
    if (!stored) return [];
    const parsed: unknown = JSON.parse(stored);
    return Array.isArray(parsed) ? (parsed as StoredTrickCalibration[]).slice(0, MAX) : [];
  } catch {
    return [];
  }
}

export async function appendTrickCalibration(capture: StoredTrickCalibration): Promise<void> {
  const existing = await loadTrickCalibrations();
  await Storage.setItem(KEY, JSON.stringify([capture, ...existing].slice(0, MAX)));
}
