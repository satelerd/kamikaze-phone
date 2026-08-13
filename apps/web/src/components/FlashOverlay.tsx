'use client';

// Full-screen white flash: the torch fallback for devices without torch API
// (iOS web). Rendered once in the root layout, driven by FXEngine.
import { useEffect, useState } from 'react';
import { FXEngine } from '@/lib/fx';

export default function FlashOverlay() {
  const [on, setOn] = useState(false);

  useEffect(() => FXEngine.onScreenFlash(setOn), []);

  return (
    <div
      aria-hidden
      className={`pointer-events-none fixed inset-0 z-[100] bg-white transition-opacity duration-75 ${
        on ? 'opacity-90' : 'opacity-0'
      }`}
    />
  );
}
