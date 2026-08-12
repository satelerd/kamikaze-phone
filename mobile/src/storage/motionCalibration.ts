import Storage from 'expo-sqlite/kv-store';

import type { AxisCalibration } from '../motion/calibration';

const KEY = 'kpf.motion-calibration-profile.v1';

export async function loadMotionCalibrationProfile(): Promise<AxisCalibration[] | null> {
  try {
    const stored = await Storage.getItem(KEY);
    if (!stored) return null;
    const parsed = JSON.parse(stored);
    return Array.isArray(parsed) ? parsed as AxisCalibration[] : null;
  } catch {
    return null;
  }
}

export async function saveMotionCalibrationProfile(profile: AxisCalibration[]): Promise<void> {
  await Storage.setItem(KEY, JSON.stringify(profile));
}
