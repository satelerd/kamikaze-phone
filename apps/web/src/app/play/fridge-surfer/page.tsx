'use client';

// Fridge Surfer: throw and land the phone on a magnetic surface (MacBook lid,
// fridge door). ThrowTracker catches the landing; the magnetometer confirms
// the magnet with a post-landing spike vs baseline. Stronger magnet = more points.
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
  MagLandingDetector, SURF_CFG, type MagVerdict, type SurfCalPhase,
} from '@/modes/fridge-surfer/logic';
import { simulateSurfThrow } from '@/modes/fridge-surfer/sim';

type Session = 'live' | 'sim' | null;

interface Outcome {
  verdict: MagVerdict;
  result: TrickResult;
  bonus: number;
}

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

export default function FridgeSurferPage() {
  const [session, setSession] = useState<Session>(null);
  const [calPhase, setCalPhase] = useState<SurfCalPhase>('idle');
  const [mag, setMag] = useState(0);
  const [delta, setDelta] = useState(0);
  const [baseline, setBaseline] = useState(0);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [streak, setStreak] = useState(0);
  const [message, setMessage] = useState('Land the phone flat on a fridge or a closed MacBook. The compass knows.');
  const [noMag, setNoMag] = useState(false);

  const detectorRef = useRef<MagLandingDetector | null>(null);
  const trackerRef = useRef<ThrowTracker | null>(null);
  const unsubsRef = useRef<(() => void)[]>([]);
  const cancelSimRef = useRef<(() => void) | null>(null);
  const streakRef = useRef(0);

  useWakeLock(session !== null);

  useEffect(() => {
    setNoMag(detectCapabilities().magnetometer !== 'yes');
    const unsubs = unsubsRef.current;
    return () => {
      detectorRef.current?.cancelPending();
      unsubs.forEach((u) => u());
      unsubs.length = 0;
      cancelSimRef.current?.();
    };
  }, []);

  const onRecord = (rec: ThrowRecord) => {
    const base = classifyThrow(rec, 'fridge-surfer');
    setMessage('Landed. Reading the magnetic field...');
    detectorRef.current?.judgeLanding(rec.landT, (v) => {
      const bonus = v.magnetic ? Math.round(Math.min(120, v.peakDelta) / 2) : 0;
      const final: TrickResult = { ...base, score: Math.min(100, base.score + bonus) };
      recordTrick(final);
      checkTrickAchievements(final);
      if (v.magnetic) {
        streakRef.current += 1;
        award('stuck-the-landing');
        if (v.peakDelta >= 100) award('full-metal');
        setMessage(`STUCK IT! ${v.peakDelta.toFixed(0)} µT of pure magnet. +${bonus} bonus.`);
        speak(
          v.peakDelta >= 100
            ? 'FULL METAL LANDING! That fridge just adopted your phone!'
            : 'Magnetic! The fridge accepts your offering, dude!',
          { style: 'surfer' },
        );
      } else {
        streakRef.current = 0;
        setMessage(
          v.samples === 0
            ? 'No mag readings after landing. Was that even near a magnet?'
            : `Plastic city. Only ${v.peakDelta.toFixed(0)} µT of deviation. Aim for the fridge!`,
        );
      }
      setStreak(streakRef.current);
      setOutcome({ verdict: v, result: final, bonus });
    });
  };

  const onEvent = (e: GameEvent) => {
    FXEngine.handle(e);
    if (e.type === 'launch') setMessage('AIRBORNE! Stick it to the metal!');
  };

  const makeRig = () => {
    trackerRef.current = new ThrowTracker(onRecord, onEvent);
    detectorRef.current = new MagLandingDetector({
      onPhase: setCalPhase,
      onCalibrated: (b) => {
        setBaseline(b);
        setMessage('Calibrated! Now throw it at something magnetic.');
        speak('Compass zeroed. Surf that fridge!', { style: 'surfer' });
      },
      onLive: (m, d) => {
        setMag(m);
        setDelta(d);
      },
    });
  };

  const wireEngine = () => {
    if (unsubsRef.current.length) return;
    const eng = SensorEngine.get();
    unsubsRef.current.push(eng.onIMU((s) => trackerRef.current?.feed(s)));
    unsubsRef.current.push(eng.onMag((s) => detectorRef.current?.feedMag(s)));
  };

  const startLive = async () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    const ok = await SensorEngine.get().requestPermission();
    if (!ok) {
      setMessage('Motion permission denied. The fridge stays lonely.');
      return;
    }
    SensorEngine.get().start();
    cancelSimRef.current?.();
    makeRig();
    wireEngine();
    detectorRef.current?.beginCalibration();
    setOutcome(null);
    setSession('live');
    setMessage('Hold it away from metal while the compass zeroes...');
  };

  const startSim = (magnetDelta: number) => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    cancelSimRef.current?.();
    makeRig();
    detectorRef.current?.beginCalibration();
    setOutcome(null);
    setSession('sim');
    setMessage('Simulating: calibration, throw, and a landing...');
    cancelSimRef.current = simulateSurfThrow(
      {
        imu: (s) => trackerRef.current?.feed(s),
        mag: (s) => detectorRef.current?.feedMag(s),
        done: () => setSession((cur) => (cur === 'sim' ? null : cur)),
      },
      { magnetDelta },
    );
  };

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-10">
      <Link href="/" className="text-sm text-zinc-400">
        ← Back to the lineup
      </Link>
      <h1 className="mt-2 text-3xl font-black">Fridge Surfer 🧲</h1>
      <p className="mt-1 text-sm text-zinc-400">
        Throw and land on a magnetic surface. A post-landing spike over{' '}
        {SURF_CFG.magneticDelta} µT means you stuck it. Stronger magnet, bigger bonus.
      </p>

      {noMag && (
        <div className="mt-4 rounded-2xl border border-amber-400/40 bg-amber-400/10 p-3 text-xs text-amber-200">
          No magnetometer API here (Android Chrome only). The simulator buttons still surf.
        </div>
      )}

      <section className="mt-4 rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
        <div className="flex items-baseline justify-between">
          <span className="text-sm font-bold text-zinc-300">
            {calPhase === 'calibrating' ? 'Calibrating...' : 'Field strength'}
          </span>
          <span className="font-mono text-2xl font-black text-amber-400">{mag.toFixed(0)} µT</span>
        </div>
        <div className="relative mt-3 h-4 overflow-hidden rounded-full bg-zinc-800">
          <div
            className="h-full bg-gradient-to-r from-amber-400 to-red-500 transition-all duration-100"
            style={{ width: `${Math.min(100, (mag / 200) * 100)}%` }}
          />
          {baseline > 0 && (
            <div
              className="absolute top-0 h-full w-0.5 bg-zinc-100"
              style={{ left: `${Math.min(100, (baseline / 200) * 100)}%` }}
            />
          )}
        </div>
        <div className="mt-2 flex justify-between text-xs text-zinc-500">
          <span>baseline {baseline.toFixed(0)} µT</span>
          <span>delta {delta.toFixed(0)} µT</span>
        </div>
      </section>

      <p className="mt-4 min-h-10 text-sm text-zinc-300">{message}</p>

      <div className="mt-4 space-y-3">
        <button
          onClick={startLive}
          className="w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
        >
          {session === 'live' ? 'RECALIBRATE 🧲' : 'SURF THE FRIDGE 🧲'}
        </button>
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={() => startSim(95)}
            className="rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 text-sm font-semibold active:scale-95"
          >
            Simulate: stick it 🖥️
          </button>
          <button
            onClick={() => startSim(12)}
            className="rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 text-sm font-semibold active:scale-95"
          >
            Simulate: plastic table 🖥️
          </button>
        </div>
      </div>

      {outcome && (
        <section
          className={`mt-6 rounded-2xl border p-4 ${
            outcome.verdict.magnetic
              ? 'border-amber-400/60 bg-amber-400/10'
              : 'border-zinc-700 bg-zinc-900'
          }`}
        >
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-black">
              {outcome.verdict.magnetic ? 'MAGNETIC LANDING 🧲' : 'Not magnetic 😔'}
            </h2>
            <span className="text-2xl font-black text-amber-400">{outcome.result.score}</span>
          </div>
          <div className="mt-2 grid grid-cols-3 gap-2 text-center text-sm">
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Trick</div>
              <div className="font-bold">{outcome.result.trickName}</div>
            </div>
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Peak delta</div>
              <div className="font-bold">{outcome.verdict.peakDelta.toFixed(0)} µT</div>
            </div>
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Magnet bonus</div>
              <div className="font-bold">+{outcome.bonus}</div>
            </div>
          </div>
          <div className="mt-3 text-xs text-zinc-400">
            Stuck-landing streak: <span className="font-bold text-amber-400">{streak}</span>
          </div>
        </section>
      )}

      <p className="mt-6 text-xs text-zinc-600">
        Best boards: fridge doors, closed MacBook lids, magnetic knife strips. Put a towel down
        first. Always the towel.
      </p>
    </main>
  );
}
