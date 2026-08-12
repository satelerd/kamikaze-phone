// Capability detection: gate by feature, never by user agent.
import type { CapabilityKey, CapabilityReport, CapabilityState, DevicePresetId } from './types';

export const CAPABILITY_LABELS: Record<CapabilityKey, string> = {
  motion: 'Motion sensors (IMU)',
  magnetometer: 'Magnetometer',
  ambientLight: 'Ambient light sensor',
  torch: 'Flashlight control',
  vibration: 'Vibration',
  battery: 'Battery / charging state',
  nfc: 'NFC',
  microphone: 'Microphone',
  camera: 'Camera',
  speech: 'Speech synthesis',
  webrtc: 'Peer-to-peer (WebRTC)',
  wakeLock: 'Keep screen awake',
};

export interface DevicePreset {
  id: DevicePresetId;
  label: string;
  blurb: string;
  /** what we expect before live detection confirms */
  expected: Partial<Record<CapabilityKey, CapabilityState>>;
}

export const DEVICE_PRESETS: DevicePreset[] = [
  {
    id: 'pixel-9',
    label: 'Pixel 9',
    blurb: 'Full sensor buffet. Torch, haptics, magnetometer, NFC: everything unlocked.',
    expected: {
      motion: 'yes', magnetometer: 'yes', ambientLight: 'yes', torch: 'yes',
      vibration: 'yes', battery: 'yes', nfc: 'yes', microphone: 'needs-permission',
      camera: 'needs-permission', speech: 'yes', webrtc: 'yes', wakeLock: 'yes',
    },
  },
  {
    id: 'iphone',
    label: 'iPhone',
    blurb: 'IMU, camera and mic are gold. Torch/vibration fall back to screen-flash + sound.',
    expected: {
      motion: 'needs-permission', magnetometer: 'no', ambientLight: 'no', torch: 'no',
      vibration: 'no', battery: 'no', nfc: 'no', microphone: 'needs-permission',
      camera: 'needs-permission', speech: 'yes', webrtc: 'yes', wakeLock: 'yes',
    },
  },
  {
    id: 'android',
    label: 'Other Android',
    blurb: 'Most sensors should work in Chrome. Live detection decides.',
    expected: { motion: 'yes', speech: 'yes', webrtc: 'yes' },
  },
  {
    id: 'desktop',
    label: 'Desktop (dev)',
    blurb: 'No sensors, all simulator. For development and spectating.',
    expected: {
      motion: 'no', magnetometer: 'no', ambientLight: 'no', torch: 'no',
      vibration: 'no', battery: 'no', nfc: 'no', microphone: 'needs-permission',
      camera: 'needs-permission', speech: 'yes', webrtc: 'yes', wakeLock: 'unknown',
    },
  },
];

function has(obj: unknown, key: string): boolean {
  return typeof obj !== 'undefined' && obj !== null && key in (obj as Record<string, unknown>);
}

/** Synchronous best-effort detection. Permission-gated features report 'needs-permission'. */
export function detectCapabilities(): CapabilityReport {
  if (typeof window === 'undefined') {
    const none = {} as CapabilityReport;
    (Object.keys(CAPABILITY_LABELS) as CapabilityKey[]).forEach((k) => (none[k] = 'unknown'));
    return none;
  }
  const iosPermission =
    has(window, 'DeviceMotionEvent') &&
    typeof (DeviceMotionEvent as unknown as { requestPermission?: unknown }).requestPermission === 'function';

  return {
    motion: has(window, 'DeviceMotionEvent') ? (iosPermission ? 'needs-permission' : 'yes') : 'no',
    magnetometer: has(window, 'Magnetometer') ? 'yes' : 'no',
    ambientLight: has(window, 'AmbientLightSensor') ? 'yes' : 'no',
    // Torch can only be confirmed with an open camera track; assume possible when camera exists.
    torch: has(navigator, 'mediaDevices') ? 'unknown' : 'no',
    vibration: has(navigator, 'vibrate') ? 'yes' : 'no',
    battery: has(navigator, 'getBattery') ? 'yes' : 'no',
    nfc: has(window, 'NDEFReader') ? 'yes' : 'no',
    microphone: has(navigator, 'mediaDevices') ? 'needs-permission' : 'no',
    camera: has(navigator, 'mediaDevices') ? 'needs-permission' : 'no',
    speech: has(window, 'speechSynthesis') ? 'yes' : 'no',
    webrtc: has(window, 'RTCPeerConnection') ? 'yes' : 'no',
    wakeLock: has(navigator, 'wakeLock') ? 'yes' : 'no',
  };
}

/** Probe torch support for real. Opens (and stops) a rear camera track. */
export async function probeTorch(): Promise<boolean> {
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
    const track = stream.getVideoTracks()[0];
    const caps = track.getCapabilities ? (track.getCapabilities() as { torch?: boolean }) : {};
    track.stop();
    return !!caps.torch;
  } catch {
    return false;
  }
}

export function capabilityOk(state: CapabilityState): boolean {
  return state === 'yes' || state === 'needs-permission' || state === 'unknown';
}
