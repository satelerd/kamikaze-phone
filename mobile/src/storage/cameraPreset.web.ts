import type { OrbitCamera } from '../components/PhoneScene3D';

const KEY = 'kpf.replay-camera-preset.v1';

export async function loadCameraPreset(): Promise<OrbitCamera | null> {
  try {
    const stored = globalThis.localStorage?.getItem(KEY);
    if (!stored) return null;
    const parsed = JSON.parse(stored) as Partial<OrbitCamera>;
    if (![parsed.azimuth, parsed.elevation, parsed.distance].every(Number.isFinite)) return null;
    return parsed as OrbitCamera;
  } catch {
    return null;
  }
}

export async function saveCameraPreset(camera: OrbitCamera): Promise<void> {
  globalThis.localStorage?.setItem(KEY, JSON.stringify(camera));
}
