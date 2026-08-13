'use client';

// Keep the screen awake during active play; re-acquire when the tab comes back.
import { useEffect } from 'react';

interface WakeLockSentinelLike {
  release(): Promise<void>;
}

type WakeLockNavigator = Navigator & {
  wakeLock?: { request(type: 'screen'): Promise<WakeLockSentinelLike> };
};

export function useWakeLock(active: boolean): void {
  useEffect(() => {
    if (!active || typeof navigator === 'undefined') return;
    const nav = navigator as WakeLockNavigator;
    if (!nav.wakeLock) return;

    let sentinel: WakeLockSentinelLike | null = null;
    let disposed = false;

    const acquire = async () => {
      try {
        const s = await nav.wakeLock!.request('screen');
        if (disposed) void s.release().catch(() => undefined);
        else sentinel = s;
      } catch {
        // Low battery or denied: the game still works, the screen may nap.
      }
    };
    void acquire();

    const onVisibility = () => {
      if (document.visibilityState === 'visible') void acquire();
    };
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      disposed = true;
      document.removeEventListener('visibilitychange', onVisibility);
      void sentinel?.release().catch(() => undefined);
      sentinel = null;
    };
  }, [active]);
}
