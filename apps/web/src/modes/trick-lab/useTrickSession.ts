'use client';

// IMU session for the Trick Lab: wires SensorEngine → ThrowTracker, maps engine
// time to performance.now() so throws can be synced against the video recorder,
// and can pump a synthetic desktop-demo throw through the exact same path.
import { useCallback, useEffect, useRef, useState } from 'react';
import { ThrowTracker, type ThrowRecord } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { FXEngine } from '@/lib/fx';
import { demoSession, generateThrow } from '@/lib/sim';
import type { GameEvent } from '@/lib/types';

export interface ThrowCapture {
  rec: ThrowRecord;
  /** performance.now() timestamps for launch / land (for video sync) */
  launchPerf: number;
  landPerf: number;
  simulated: boolean;
}

export function useTrickSession(onThrow: (t: ThrowCapture) => void) {
  const [tracking, setTracking] = useState(false);
  const [airborne, setAirborne] = useState(false);
  const [liveFlips, setLiveFlips] = useState(0);

  /** performance.now() - sample.t, refreshed on every IMU sample */
  const offsetRef = useRef(0);
  const simulatedRef = useRef(false);
  const unsubRef = useRef<(() => void) | null>(null);
  const onThrowRef = useRef(onThrow);
  onThrowRef.current = onThrow;

  const stop = useCallback(() => {
    unsubRef.current?.();
    unsubRef.current = null;
    setTracking(false);
    setAirborne(false);
  }, []);

  const start = useCallback(() => {
    if (unsubRef.current) return;
    simulatedRef.current = false;
    setLiveFlips(0);
    setAirborne(false);

    const tracker = new ThrowTracker(
      (rec) => {
        onThrowRef.current({
          rec,
          launchPerf: offsetRef.current + rec.launchT,
          landPerf: offsetRef.current + rec.landT,
          simulated: simulatedRef.current,
        });
      },
      (e: GameEvent) => {
        FXEngine.handle(e);
        if (e.type === 'launch') {
          setAirborne(true);
          setLiveFlips(0);
        } else if (e.type === 'flip') {
          setLiveFlips(e.count);
        } else if (e.type === 'catch') {
          setAirborne(false);
        }
      },
    );

    const engine = SensorEngine.get();
    const unsub = engine.onIMU((s) => {
      // Samples arrive (near) live, so this maps engine time → wall clock.
      offsetRef.current = performance.now() - s.t;
      tracker.feed(s);
    });
    unsubRef.current = unsub;
    engine.start();
    setTracking(true);
  }, []);

  /** Desktop demo: replay a synthetic throw through the real engine, realtime. */
  const simulate = useCallback(async (): Promise<string> => {
    const menu = demoSession();
    const pick = menu[Math.floor(Math.random() * menu.length)];
    simulatedRef.current = true;
    await SensorEngine.get().injectSamples(generateThrow(pick.params), true);
    return pick.label;
  }, []);

  useEffect(() => stop, [stop]);

  return { start, stop, simulate, tracking, airborne, liveFlips };
}
