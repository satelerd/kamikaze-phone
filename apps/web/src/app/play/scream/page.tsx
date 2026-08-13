'use client';

// Scream Meter: a 3 second hype scream sets a 1.0x..2.0x multiplier on your
// next throw. The mic also listens for the whoosh of the phone slicing air
// mid-flight for a style bonus. Mic is released on unmount.
import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { award, checkTrickAchievements } from '@/lib/achievements';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import { classifyThrow, ThrowTracker, type ThrowRecord } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { speak } from '@/lib/speech';
import { recordTrick } from '@/lib/store';
import type { GameEvent, TrickResult } from '@/lib/types';
import {
  MicMeter, multiplierFromDb, rmsToDb, screamLine, SCREAM_CFG, type MicLevel,
} from '@/modes/scream/logic';
import { simulateScreamLevels, simulateScreamThrow } from '@/modes/scream/sim';

type Phase = 'idle' | 'mic-ready' | 'hyping' | 'armed' | 'done';

interface Outcome {
  baseScore: number;
  mult: number;
  whoosh: boolean;
  result: TrickResult;
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

export default function ScreamPage() {
  const [phase, setPhase] = useState<Phase>('idle');
  const [level, setLevel] = useState<MicLevel>({ rms: 0, db: -80 });
  const [hypeLeft, setHypeLeft] = useState(0);
  const [mult, setMult] = useState<number | null>(null);
  const [peakDb, setPeakDb] = useState(-80);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [message, setMessage] = useState('Mic check first. Then scream your lungs out and throw.');
  const [simActive, setSimActive] = useState(false);

  const phaseRef = useRef<Phase>('idle');
  const meterRef = useRef<MicMeter | null>(null);
  const trackerRef = useRef<ThrowTracker | null>(null);
  const unsubRef = useRef<(() => void) | null>(null);
  const peakRmsRef = useRef(0);
  const idleEmaRef = useRef(0.01);
  const flightPeakRef = useRef(0);
  const inFlightRef = useRef(false);
  const reactedRef = useRef(false);
  const multRef = useRef(1);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const cancelSimRef = useRef<(() => void) | null>(null);

  useWakeLock(phase !== 'idle');

  useEffect(() => {
    return () => {
      meterRef.current?.stop();
      meterRef.current = null;
      unsubRef.current?.();
      unsubRef.current = null;
      cancelSimRef.current?.();
      timersRef.current.forEach(clearTimeout);
      timersRef.current = [];
    };
  }, []);

  const setPhaseBoth = (p: Phase) => {
    phaseRef.current = p;
    setPhase(p);
  };

  const handleLevel = (lv: MicLevel) => {
    setLevel(lv);
    const ph = phaseRef.current;
    if (ph === 'hyping') {
      if (lv.rms > peakRmsRef.current) {
        peakRmsRef.current = lv.rms;
        setPeakDb(rmsToDb(lv.rms));
      }
      if (lv.rms > SCREAM_CFG.instantReactRms && !reactedRef.current) {
        reactedRef.current = true;
        speak('THERE IT IS! Keep it coming!', { style: 'surfer', interrupt: true });
      }
    } else if (inFlightRef.current) {
      flightPeakRef.current = Math.max(flightPeakRef.current, lv.rms);
    } else {
      idleEmaRef.current = idleEmaRef.current * 0.95 + lv.rms * 0.05;
    }
  };

  const onRecord = (rec: ThrowRecord) => {
    inFlightRef.current = false;
    const m = multRef.current;
    const base = classifyThrow(rec, 'scream');
    const whoosh =
      flightPeakRef.current >
      Math.max(SCREAM_CFG.whooshFloorRms, idleEmaRef.current * SCREAM_CFG.whooshIdleFactor);
    const bonus = whoosh ? SCREAM_CFG.whooshBonus : 0;
    const final: TrickResult = { ...base, score: Math.min(100, Math.round(base.score * m) + bonus) };
    recordTrick(final);
    checkTrickAchievements(final);
    if (whoosh) award('heard-the-whoosh');
    setOutcome({ baseScore: base.score, mult: m, whoosh, result: final });
    setPhaseBoth('done');
    setMessage(
      whoosh
        ? 'The mic HEARD the whoosh. Style bonus banked!'
        : 'Landed. Silent flight though. Spin it harder for the whoosh.',
    );
    if (whoosh) speak('I heard the whoosh! That phone was singing!', { style: 'surfer' });
  };

  const onEvent = (e: GameEvent) => {
    FXEngine.handle(e);
    if (e.type === 'launch') {
      inFlightRef.current = true;
      flightPeakRef.current = 0;
    }
  };

  const ensureTracker = () => {
    if (!trackerRef.current) trackerRef.current = new ThrowTracker(onRecord, onEvent);
    return trackerRef.current;
  };

  const micCheck = async () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-select' });
    ensureTracker();
    const motionOk = await SensorEngine.get().requestPermission();
    if (motionOk) {
      SensorEngine.get().start();
      if (!unsubRef.current) {
        unsubRef.current = SensorEngine.get().onIMU((s) => trackerRef.current?.feed(s));
      }
    }
    if (!meterRef.current?.running) {
      const meter = new MicMeter(handleLevel);
      const ok = await meter.start();
      if (!ok) {
        setMessage('Mic denied or unavailable. Use the simulator, or check permissions.');
        return;
      }
      meterRef.current = meter;
    }
    setPhaseBoth('mic-ready');
    setMessage('Mic is HOT. Hit the hype scream when ready.');
  };

  const finalizeHype = (finalPeakDb: number) => {
    const m = multiplierFromDb(finalPeakDb);
    multRef.current = m;
    setMult(m);
    setPeakDb(finalPeakDb);
    setPhaseBoth('armed');
    setMessage(`Multiplier locked: ${m.toFixed(2)}x. NOW THROW IT!`);
    speak(screamLine(m), { style: 'surfer', interrupt: true });
    if (m >= SCREAM_CFG.bansheeMultiplier) award('banshee');
  };

  const startHype = () => {
    FXEngine.handle({ type: 'ui-start' });
    peakRmsRef.current = 0;
    reactedRef.current = false;
    setPeakDb(-80);
    setOutcome(null);
    setPhaseBoth('hyping');
    setHypeLeft(3);
    setMessage('SCREAM! Louder means a bigger multiplier!');
    const iv = setInterval(() => setHypeLeft((n) => Math.max(0, n - 1)), 1000);
    timersRef.current.push(
      setTimeout(() => {
        clearInterval(iv);
        finalizeHype(rmsToDb(peakRmsRef.current));
      }, SCREAM_CFG.hypeWindowMs),
    );
  };

  const startSim = () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    cancelSimRef.current?.();
    ensureTracker();
    setSimActive(true);
    setOutcome(null);
    peakRmsRef.current = 0;
    reactedRef.current = false;
    setPhaseBoth('hyping');
    setHypeLeft(3);
    setMessage('Simulating a hype scream...');
    const iv = setInterval(() => setHypeLeft((n) => Math.max(0, n - 1)), 1000);
    cancelSimRef.current = simulateScreamLevels(handleLevel, (simPeakDb) => {
      clearInterval(iv);
      finalizeHype(simPeakDb);
      setMessage('Simulated scream done. Simulating the throw...');
      cancelSimRef.current = simulateScreamThrow({
        imu: (s) => trackerRef.current?.feed(s),
        level: handleLevel,
        done: () => setSimActive(false),
      });
    });
  };

  const meterPct = Math.max(0, Math.min(100, ((level.db + 60) / 60) * 100));
  const multLive = phase === 'hyping' ? multiplierFromDb(peakDb) : mult ?? 1;

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-10">
      <Link href="/" className="text-sm text-zinc-400">
        ← Back to the lineup
      </Link>
      <h1 className="mt-2 text-3xl font-black">Scream Meter 📣</h1>
      <p className="mt-1 text-sm text-zinc-400">
        Hype scream for 3 seconds to set a score multiplier, then throw. The mic also scores the
        whoosh of the flight.
      </p>

      <section className="mt-4 rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
        <div className="flex items-baseline justify-between">
          <span className="text-sm font-bold text-zinc-300">Mic level</span>
          <span className="font-mono text-2xl font-black text-amber-400">
            {level.db.toFixed(0)} dB
          </span>
        </div>
        <div className="mt-3 h-6 overflow-hidden rounded-full bg-zinc-800">
          <div
            className={`h-full transition-all duration-75 ${
              meterPct > 80
                ? 'bg-red-500'
                : meterPct > 55
                  ? 'bg-amber-400'
                  : 'bg-emerald-400'
            }`}
            style={{ width: `${meterPct}%` }}
          />
        </div>
        <div className="mt-2 flex justify-between text-xs text-zinc-500">
          <span>peak {peakDb.toFixed(0)} dB</span>
          <span className="font-bold text-amber-400">{multLive.toFixed(2)}x</span>
        </div>
      </section>

      {phase === 'hyping' && (
        <div className="mt-4 rounded-2xl border border-amber-400/60 bg-amber-400/10 p-4 text-center">
          <div className="text-4xl font-black text-amber-400">{hypeLeft || 'GO'}</div>
          <div className="mt-1 text-sm text-amber-200">SCREAM NOW</div>
        </div>
      )}

      <p className="mt-4 min-h-10 text-sm text-zinc-300">{message}</p>

      <div className="mt-4 space-y-3">
        {phase === 'idle' && (
          <button
            onClick={micCheck}
            className="w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
          >
            MIC CHECK 🎙️
          </button>
        )}
        {(phase === 'mic-ready' || phase === 'armed' || phase === 'done') && (
          <button
            onClick={startHype}
            disabled={!meterRef.current?.running}
            className="w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 disabled:opacity-40 active:scale-95"
          >
            HYPE SCREAM 📣
          </button>
        )}
        {phase === 'armed' && (
          <div className="rounded-2xl border border-emerald-400/50 bg-emerald-400/10 p-3 text-center text-sm text-emerald-300">
            Armed at {mult?.toFixed(2)}x. Throw the phone whenever you are ready!
          </div>
        )}
        <button
          onClick={startSim}
          disabled={simActive}
          className="w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold disabled:opacity-40 active:scale-95"
        >
          Simulate scream + throw 🖥️
        </button>
      </div>

      {outcome && (
        <section className="mt-6 rounded-2xl border border-amber-400/50 bg-zinc-900 p-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-black">{outcome.result.trickName}</h2>
            <span className="text-3xl font-black text-amber-400">{outcome.result.score}</span>
          </div>
          <div className="mt-2 text-sm text-zinc-300">
            {outcome.baseScore} base x {outcome.mult.toFixed(2)} scream
            {outcome.whoosh ? ` + ${SCREAM_CFG.whooshBonus} whoosh` : ''} = {outcome.result.score}
          </div>
          <div className="mt-2 grid grid-cols-3 gap-2 text-center text-sm">
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Grade</div>
              <div className="font-bold">{outcome.result.grade}</div>
            </div>
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Airtime</div>
              <div className="font-bold">{outcome.result.features.airtime.toFixed(2)}s</div>
            </div>
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Whoosh</div>
              <div className="font-bold">{outcome.whoosh ? '💨 YES' : 'nope'}</div>
            </div>
          </div>
        </section>
      )}

      <p className="mt-6 text-xs text-zinc-600">
        A {SCREAM_CFG.bansheeMultiplier.toFixed(2)}x scream earns the Banshee badge. Warn your
        roommates. Or do not.
      </p>
    </main>
  );
}
