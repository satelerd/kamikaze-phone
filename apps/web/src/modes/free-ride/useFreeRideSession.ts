'use client';

// Free Ride session engine: wires SensorEngine -> ThrowTracker -> classifier
// -> store + narrator + FX, and exposes phase / stats / feed to the page.
// Also drives the desktop demo (simulated throws through the same pipeline).
import { useCallback, useEffect, useRef, useState } from 'react';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import { Narrator } from '@/lib/narrator';
import { ThrowTracker, classifyThrow, type ThrowRecord } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { demoSession, generateThrow } from '@/lib/sim';
import { recordTrick } from '@/lib/store';
import type { GameEvent, IMUSample, TrickResult } from '@/lib/types';

export type UiPhase = 'chilling' | 'windup' | 'airborne' | 'caught';

export interface FeedItem {
  uid: string;
  result: TrickResult;
  /** what Bodhi said about this throw */
  line: string | null;
}

export interface SessionStats {
  throws: number;
  streak: number;
  best: number;
  biggestAir: number;
}

const EMPTY_STATS: SessionStats = { throws: 0, streak: 0, best: 0, biggestAir: 0 };

async function checkAchievements(result: TrickResult): Promise<void> {
  try {
    const mod = await import('@/lib/achievements');
    mod.checkTrickAchievements(result);
  } catch {
    // achievements must never break a session
  }
}

function uid(): string {
  return typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

export function useFreeRideSession() {
  const [running, setRunning] = useState(false);
  const [permissionError, setPermissionError] = useState(false);
  const [phase, setPhaseState] = useState<UiPhase>('chilling');
  const [flips, setFlips] = useState(0);
  const [feed, setFeed] = useState<FeedItem[]>([]);
  const [stats, setStats] = useState<SessionStats>(EMPTY_STATS);
  const [simulating, setSimulating] = useState(false);

  const runningRef = useRef(false);
  const simulatingRef = useRef(false);
  const trackerRef = useRef<ThrowTracker | null>(null);
  const unsubRef = useRef<(() => void) | null>(null);
  const wakeLockRef = useRef<WakeLockSentinel | null>(null);
  const phaseRef = useRef<UiPhase>('chilling');
  const windupTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const caughtTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const streakRef = useRef(0);

  const setPhase = useCallback((p: UiPhase) => {
    phaseRef.current = p;
    setPhaseState(p);
  }, []);

  const handleEvent = useCallback(
    (e: GameEvent) => {
      FXEngine.handle(e);
      Narrator.onEvent(e);
      if (e.type === 'launch') {
        if (windupTimer.current) clearTimeout(windupTimer.current);
        setFlips(0);
        setPhase('airborne');
      } else if (e.type === 'flip') {
        setFlips(e.count);
      } else if (e.type === 'catch') {
        setPhase('caught');
        if (caughtTimer.current) clearTimeout(caughtTimer.current);
        caughtTimer.current = setTimeout(() => {
          if (phaseRef.current === 'caught') setPhase('chilling');
        }, 1600);
      }
    },
    [setPhase],
  );

  const handleRecord = useCallback((rec: ThrowRecord) => {
    const result = classifyThrow(rec, 'free-ride');
    recordTrick(result);
    const line = Narrator.onTrick(result);
    FXEngine.handle({ type: 'trick', result });
    void checkAchievements(result);

    streakRef.current =
      result.features.caught && result.grade !== 'BAIL' ? streakRef.current + 1 : 0;
    setStats((s) => ({
      throws: s.throws + 1,
      streak: streakRef.current,
      best: Math.max(s.best, result.score),
      biggestAir: Math.max(s.biggestAir, result.features.airtime),
    }));
    setFeed((f) => [{ uid: uid(), result, line }, ...f].slice(0, 30));
  }, []);

  const handleSample = useCallback(
    (s: IMUSample) => {
      const tracker = trackerRef.current;
      if (!tracker) return;
      tracker.feed(s);
      // Windup hint for the UI: hard acceleration while still in hand.
      if (tracker.phase !== 'airborne' && tracker.phase !== 'impact') {
        const aTotal = Math.hypot(s.ax, s.ay, s.az);
        if (aTotal > 16 && phaseRef.current !== 'airborne') {
          if (phaseRef.current !== 'windup') setPhase('windup');
          if (windupTimer.current) clearTimeout(windupTimer.current);
          windupTimer.current = setTimeout(() => {
            if (phaseRef.current === 'windup') setPhase('chilling');
          }, 500);
        }
      }
    },
    [setPhase],
  );

  /** Shared session bootstrap for both real sensors and the simulator. */
  const beginSession = useCallback(() => {
    if (runningRef.current) return;
    runningRef.current = true;
    setRunning(true);
    setStats(EMPTY_STATS);
    streakRef.current = 0;
    Narrator.attach('free-ride');
    trackerRef.current = new ThrowTracker(handleRecord, handleEvent);
    unsubRef.current = SensorEngine.get().onIMU(handleSample);
    FXEngine.handle({ type: 'ui-start' });
  }, [handleEvent, handleRecord, handleSample]);

  const acquireWakeLock = useCallback(async () => {
    try {
      if (typeof navigator !== 'undefined' && 'wakeLock' in navigator) {
        wakeLockRef.current = await navigator.wakeLock.request('screen');
      }
    } catch {
      // wake lock denied (low battery etc.); session still works
    }
  }, []);

  /** Real session: sensor permission + wake lock + audio + narrator. */
  const start = useCallback(async () => {
    AudioBus.ensure();
    const engine = SensorEngine.get();
    const ok = await engine.requestPermission();
    if (!ok) {
      setPermissionError(true);
      return;
    }
    setPermissionError(false);
    engine.start();
    await acquireWakeLock();
    void AudioBus.playMusic();
    beginSession();
  }, [acquireWakeLock, beginSession]);

  /** Desktop demo: replay demoSession() through the exact same pipeline. */
  const simulate = useCallback(async () => {
    if (simulatingRef.current) return;
    simulatingRef.current = true;
    setSimulating(true);
    AudioBus.ensure();
    if (!runningRef.current) beginSession();
    const engine = SensorEngine.get();
    for (const demo of demoSession()) {
      if (!runningRef.current) break;
      trackerRef.current?.reset();
      const samples = generateThrow(demo.params, 0);
      await engine.injectSamples(samples, true);
      // give Bodhi a beat to call it before the next throw
      await new Promise((r) => setTimeout(r, 1200));
    }
    simulatingRef.current = false;
    setSimulating(false);
  }, [beginSession]);

  const stop = useCallback(() => {
    if (!runningRef.current) return;
    runningRef.current = false;
    setRunning(false);
    unsubRef.current?.();
    unsubRef.current = null;
    trackerRef.current = null;
    Narrator.detach();
    AudioBus.stopMusic();
    SensorEngine.get().stop();
    void wakeLockRef.current?.release().catch(() => {});
    wakeLockRef.current = null;
    if (windupTimer.current) clearTimeout(windupTimer.current);
    if (caughtTimer.current) clearTimeout(caughtTimer.current);
    setPhase('chilling');
  }, [setPhase]);

  // Teardown on page leave.
  useEffect(() => stop, [stop]);

  return {
    running,
    permissionError,
    phase,
    flips,
    feed,
    stats,
    simulating,
    start,
    stop,
    simulate,
  };
}
