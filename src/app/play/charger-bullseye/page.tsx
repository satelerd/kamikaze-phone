'use client';

// Charger Bullseye: toss the phone onto a wireless charger pad. If
// battery.charging flips true within 3 seconds of the detected landing,
// that is a BULLSEYE. Works with wireless chargers (Pixel Stand, MagSafe pads).
import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { award, checkTrickAchievements } from '@/lib/achievements';
import { AudioBus } from '@/lib/audio';
import { detectCapabilities } from '@/lib/capabilities';
import { FXEngine } from '@/lib/fx';
import { classifyThrow, ThrowTracker, type ThrowRecord } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { speak } from '@/lib/speech';
import { recordTrick } from '@/lib/store';
import type { GameEvent, TrickResult } from '@/lib/types';
import {
  BullseyeJudge, BULLSEYE_CFG, getBattery, type BatteryLike,
} from '@/modes/charger-bullseye/logic';
import { simulateBullseyeThrow } from '@/modes/charger-bullseye/sim';

type Phase = 'idle' | 'armed' | 'waiting' | 'hit' | 'miss';

function useWakeLock(active: boolean): void {
  useEffect(() => {
    if (!active) return;
    let sentinel: WakeLockSentinel | null = null;
    let cancelled = false;
    const request = async () => {
      try {
        if ('wakeLock' in navigator) {
          sentinel = await navigator.wakeLock.request('screen');
          if (cancelled) await sentinel.release();
        }
      } catch {
        // wake lock unavailable
      }
    };
    void request();
    const onVis = () => {
      if (document.visibilityState === 'visible') void request();
    };
    document.addEventListener('visibilitychange', onVis);
    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVis);
      void sentinel?.release().catch(() => {});
    };
  }, [active]);
}

function Rings({ phase }: { phase: Phase }) {
  const hot = phase === 'hit';
  const waiting = phase === 'waiting';
  return (
    <div className="relative mx-auto mt-4 w-56">
      <svg viewBox="0 0 200 200" className={`w-full ${waiting ? 'animate-pulse' : ''}`}>
        <circle
          cx="100" cy="100" r="90" strokeWidth="10"
          className={`fill-none ${hot ? 'stroke-amber-400/40' : 'stroke-zinc-800'}`}
        />
        <circle
          cx="100" cy="100" r="65" strokeWidth="10"
          className={`fill-none ${hot ? 'stroke-amber-400/60' : 'stroke-zinc-700'}`}
        />
        <circle
          cx="100" cy="100" r="40" strokeWidth="10"
          className={`fill-none ${hot ? 'stroke-amber-400/80' : 'stroke-zinc-600'}`}
        />
        <circle
          cx="100" cy="100" r="16"
          className={hot ? 'fill-amber-400' : 'fill-zinc-700'}
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center text-3xl">
        {hot ? '⚡' : waiting ? '⏳' : '🔋'}
      </div>
    </div>
  );
}

export default function ChargerBullseyePage() {
  const [phase, setPhase] = useState<Phase>('idle');
  const [charging, setCharging] = useState(false);
  const [batterySupport, setBatterySupport] = useState<boolean | null>(null);
  const [streak, setStreak] = useState(0);
  const [bestStreak, setBestStreak] = useState(0);
  const [points, setPoints] = useState(0);
  const [lastPts, setLastPts] = useState(0);
  const [latency, setLatency] = useState<number | null>(null);
  const [lastTrick, setLastTrick] = useState<TrickResult | null>(null);
  const [message, setMessage] = useState('Park a wireless charger on a towel. Then bomb it from range.');
  const [simActive, setSimActive] = useState(false);

  const judgeRef = useRef<BullseyeJudge>(new BullseyeJudge());
  const trackerRef = useRef<ThrowTracker | null>(null);
  const unsubRef = useRef<(() => void) | null>(null);
  const cancelSimRef = useRef<(() => void) | null>(null);
  const streakRef = useRef(0);

  useWakeLock(phase !== 'idle');

  useEffect(() => {
    const judge = judgeRef.current;
    const p = getBattery();
    if (!p) {
      setBatterySupport(false);
    } else {
      let bat: BatteryLike | null = null;
      const onChange = () => {
        if (!bat) return;
        setCharging(bat.charging);
        judge.noteCharging(bat.charging);
      };
      void p.then((b) => {
        bat = b;
        setBatterySupport(true);
        setCharging(b.charging);
        judge.prime(b.charging);
        b.addEventListener('chargingchange', onChange);
      });
      return () => {
        bat?.removeEventListener('chargingchange', onChange);
        judge.cancel();
        unsubRef.current?.();
        unsubRef.current = null;
        cancelSimRef.current?.();
      };
    }
    return () => {
      judge.cancel();
      unsubRef.current?.();
      unsubRef.current = null;
      cancelSimRef.current?.();
    };
  }, []);

  const onRecord = (rec: ThrowRecord) => {
    const result = classifyThrow(rec, 'charger-bullseye');
    setLastTrick(result);
    const landAt = performance.now() - rec.settleMs;
    setPhase('waiting');
    setMessage('Landed... listening for juice...');
    judgeRef.current.noteLanding(landAt, (v) => {
      recordTrick(result);
      checkTrickAchievements(result);
      if (v.hit) {
        const pts = 100 + Math.max(0, 50 - Math.round(v.latencyMs / 60));
        streakRef.current += 1;
        setStreak(streakRef.current);
        setBestStreak((b) => Math.max(b, streakRef.current));
        setPoints((total) => total + pts);
        setLastPts(pts);
        setLatency(v.latencyMs);
        setPhase('hit');
        setMessage(`BULLSEYE! Juice detected ${(v.latencyMs / 1000).toFixed(1)}s after touchdown.`);
        award('dead-center');
        if (streakRef.current >= 3) award('triple-juice');
        void AudioBus.play('fanfare');
        speak('BULLSEYE! Dead center on the juice pad!', { style: 'surfer' });
      } else {
        streakRef.current = 0;
        setStreak(0);
        setLatency(null);
        setPhase('miss');
        setMessage('No juice. Off the pad. Scoot it over and fire again!');
        speak('So close! Nudge it onto the pad next time.', { style: 'surfer' });
      }
    });
  };

  const onEvent = (e: GameEvent) => {
    FXEngine.handle(e);
    if (e.type === 'launch') setMessage('AIRBORNE! Aim for the pad!');
  };

  const ensureTracker = () => {
    if (!trackerRef.current) trackerRef.current = new ThrowTracker(onRecord, onEvent);
    return trackerRef.current;
  };

  const arm = async () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    const ok = await SensorEngine.get().requestPermission();
    if (!ok) {
      setMessage('Motion permission denied. The pad waits in vain.');
      return;
    }
    SensorEngine.get().start();
    ensureTracker();
    if (!unsubRef.current) {
      unsubRef.current = SensorEngine.get().onIMU((s) => trackerRef.current?.feed(s));
    }
    setPhase('armed');
    setMessage(
      charging
        ? 'Phone is already charging! Yank it off the pad first, then throw.'
        : 'Armed. Toss it onto the charger pad!',
    );
  };

  const startSim = (forceHit?: boolean) => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    cancelSimRef.current?.();
    ensureTracker();
    setSimActive(true);
    setPhase('armed');
    setMessage('Simulating a toss at the pad...');
    cancelSimRef.current = simulateBullseyeThrow(
      (s) => trackerRef.current?.feed(s),
      (on) => {
        setCharging(on);
        judgeRef.current.noteCharging(on);
        if (!on) setSimActive(false);
      },
      { hit: forceHit },
    );
    // if the sim never flips charging, the judge timeout ends the round
    setTimeout(() => setSimActive(false), 8000);
  };

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-10">
      <Link href="/" className="text-sm text-zinc-400">
        ← Back to the lineup
      </Link>
      <h1 className="mt-2 text-3xl font-black">Charger Bullseye 🎯</h1>
      <p className="mt-1 text-sm text-zinc-400">
        Land on the wireless charger. If charging flips on within{' '}
        {BULLSEYE_CFG.windowMs / 1000} seconds of touchdown, that is a bullseye.
      </p>

      {batterySupport === false && (
        <div className="mt-4 rounded-2xl border border-amber-400/40 bg-amber-400/10 p-3 text-xs text-amber-200">
          No Battery Status API here (Android Chrome only). Simulator still throws darts.
        </div>
      )}

      <div className="mt-4 flex items-center gap-2">
        <span
          className={`rounded-full px-3 py-1 text-xs font-bold ${
            charging ? 'bg-emerald-400/20 text-emerald-300' : 'bg-zinc-800 text-zinc-400'
          }`}
        >
          {charging ? '⚡ charging' : 'not charging'}
        </span>
        <span className="rounded-full bg-zinc-800 px-3 py-1 text-xs font-bold text-amber-400">
          streak {streak}
        </span>
        <span className="rounded-full bg-zinc-800 px-3 py-1 text-xs text-zinc-400">
          best {bestStreak}
        </span>
      </div>

      <Rings phase={phase} />

      {phase === 'hit' && (
        <div className="mt-2 text-center">
          <div className="text-2xl font-black text-amber-400">BULLSEYE! +{lastPts}</div>
          {latency !== null && (
            <div className="text-xs text-zinc-400">
              juice in {(latency / 1000).toFixed(1)}s{lastTrick ? `, ${lastTrick.trickName} on the way down` : ''}
            </div>
          )}
        </div>
      )}
      {phase === 'miss' && (
        <div className="mt-2 text-center text-lg font-black text-zinc-400">OFF THE PAD 😤</div>
      )}

      <p className="mt-4 min-h-10 text-center text-sm text-zinc-300">{message}</p>

      <div className="mt-4 space-y-3">
        <button
          onClick={arm}
          className="w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
        >
          {phase === 'idle' ? 'ARM THE RANGE 🎯' : 'REARM 🎯'}
        </button>
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={() => startSim(true)}
            disabled={simActive}
            className="rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 text-sm font-semibold disabled:opacity-40 active:scale-95"
          >
            Simulate: hit 🖥️
          </button>
          <button
            onClick={() => startSim(false)}
            disabled={simActive}
            className="rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 text-sm font-semibold disabled:opacity-40 active:scale-95"
          >
            Simulate: miss 🖥️
          </button>
        </div>
      </div>

      <div className="mt-6 flex justify-between rounded-2xl border border-zinc-700 bg-zinc-900 p-4 text-sm">
        <span className="text-zinc-400">Session points</span>
        <span className="font-black text-amber-400">{points}</span>
      </div>

      <p className="mt-6 text-xs text-zinc-600">
        Works with wireless chargers: Pixel Stand, MagSafe pads, generic Qi discs. Cable chargers
        count too if you are feeling surgical. Three in a row = Triple Juice.
      </p>
    </main>
  );
}
