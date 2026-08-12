'use client';
import { useState } from 'react';

export default function useSensorPermissions() {
  const [granted, setGranted] = useState(false);
  const [attempted, setAttempted] = useState(false);

  const request = async () => {
    setAttempted(true);
    try {
      let motion = true;
      let orientation = true;
      if (typeof (DeviceMotionEvent as any).requestPermission === 'function') {
        const perm = await (DeviceMotionEvent as any).requestPermission();
        motion = perm === 'granted';
      }
      if (typeof (DeviceOrientationEvent as any).requestPermission === 'function') {
        const perm = await (DeviceOrientationEvent as any).requestPermission();
        orientation = perm === 'granted';
      }
      setGranted(motion && orientation);
    } catch {
      setGranted(false);
    }
  };

  return { granted, attempted, request };
}
