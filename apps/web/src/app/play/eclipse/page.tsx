'use client';

// Eclipse: throw the phone through darkness (under a couch, through a towel
// tunnel). The ambient light sensor records the flight; the darkness dip is
// the score. Full blackout = under 2 lux mid-flight in a bright room.
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
import type { GameEvent, LuxSample, TrickResult } from '@/lib/types';
import { LuxRecorder, type EclipseVerdict } from '@/modes/eclipse/logic';
import { simulateEclipseThrow } from '@/modes/eclipse/sim';

type Session = 'live' | 'sim' | null;

interface Outcome {
  verdict: EclipseVerdict;
  result: TrickResult;
  launchT: number;
  landT: number;
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

function LuxChart({ outcome }: { outcome: Outcome }) {
  const { chart } = outcome.verdict;
  if (chart.length < 2) {
    return (
      <p className="text-xs text-zinc-500">
        Not enough light samples for a chart. That sensor naps at 10 Hz.
      </p>
    );
  }
  const t0 = chart[0].t;
  const t1 = chart[chart.length - 1].t;
  const span = Math.max(1, t1 - t0);
  const maxLux = Math.max(outcome.verdict.baseline * 1.2, ...chart.map((c) => c.lux), 10);
  const X = (t: number) => ((t - t0) / span) * 300;
  const Y = (lux: number) => 76 - (lux / maxLux) * 70;
  const pts = chart.map((c: LuxSample) => `${X(c.t).toFixed(1)},${Y(c.lux).toFixed(1)}`).join(' ');
  return (
    <svg viewBox="0 0 300 80" className="mt-2 w-full">
      <rect
        x={X(Math.max(t0, outcome.launchT))}
        y={0}
        width={Math.max(2, X(Math.min(t1, outcome.landT)) - X(Math.max(t0, outcome.launchT)))}
        height={80}
        className="fill-amber-400/10"
      />
      <line
        x1={0}
        x2={300}
        y1={Y(outcome.verdict.baseline)}
        y2={Y(outcome.verdict.baseline)}
        className="stroke-zinc-600"
        strokeDasharray="4 3"
        strokeWidth={1}
      />
      <polyline points={pts} fill="none" className="stroke-amber-400" strokeWidth={2} />
    </svg>
  );
}

export default function EclipsePage() {
  const [session, setSession] = useState<Session>(null);
  const [lux, setLux] = useState(0);
  const [baseline, setBaseline] = useState(0);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [message, setMessage] = useState('Throw through a shadow: under the couch, through a towel tunnel, behind the fridge.');
  const [noLux, setNoLux] = useState(false);

  const recorderRef = useRef<LuxRecorder | null>(null);
  const trackerRef = useRef<ThrowTracker | null>(null);
  const unsubsRef = useRef<(() => void)[]>([]);
  const cancelSimRef = useRef<(() => void) | null>(null);

  useWakeLock(session !== null);

  useEffect(() => {
    setNoLux(detectCapabilities().ambientLight !== 'yes');
    const unsubs = unsubsRef.current;
    return () => {
      unsubs.forEach((u) => u());
      unsubs.length = 0;
      cancelSimRef.current?.();
    };
  }, []);

  const onRecord = (rec: ThrowRecord) => {
    const recorder = recorderRef.current;
    if (!recorder) return;
    recorder.setInFlight(false);
    const verdict = recorder.judge(rec.launchT, rec.landT);
    const base = classifyThrow(rec, 'eclipse');
    const final: TrickResult = { ...base, score: Math.min(100, base.score + verdict.bonus) };
    recordTrick(final);
    checkTrickAchievements(final);
    if (verdict.fullBlackout) award('total-eclipse');
    if (verdict.dipRatio >= 0.8) award('shadow-dancer');
    setOutcome({ verdict, result: final, launchT: rec.launchT, landT: rec.landT });
    if (verdict.fullBlackout) {
      setMessage('FULL BLACKOUT! The phone visited the shadow realm.');
      speak('TOTAL ECLIPSE! That phone went full vampire, dude!', { style: 'surfer' });
    } else if (verdict.dipRatio > 0.4) {
      setMessage(`Nice dip: ${Math.round(verdict.dipRatio * 100)}% darker mid-flight.`);
      speak('Ooo, a taste of the dark side. Deeper next time!', { style: 'surfer' });
    } else if (verdict.samples === 0) {
      setMessage('No light samples during flight. The sensor blinked. Throw again.');
    } else {
      setMessage('Barely a shadow. Find darker air, brah.');
    }
  };

  const onEvent = (e: GameEvent) => {
    FXEngine.handle(e);
    if (e.type === 'launch') {
      recorderRef.current?.setInFlight(true);
      setMessage('AIRBORNE! Into the dark...');
    }
    if (e.type === 'catch' || e.type === 'bail') recorderRef.current?.setInFlight(false);
  };

  const makeRig = () => {
    recorderRef.current = new LuxRecorder();
    trackerRef.current = new ThrowTracker(onRecord, onEvent);
  };

  const handleLux = (s: LuxSample) => {
    recorderRef.current?.feedLux(s);
    setLux(s.lux);
    if (recorderRef.current) setBaseline(recorderRef.current.baseline);
  };

  const wireEngine = () => {
    if (unsubsRef.current.length) return;
    const eng = SensorEngine.get();
    unsubsRef.current.push(eng.onIMU((s) => trackerRef.current?.feed(s)));
    unsubsRef.current.push(eng.onLux(handleLux));
  };

  const startLive = async () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    const ok = await SensorEngine.get().requestPermission();
    if (!ok) {
      setMessage('Motion permission denied. The shadows stay unexplored.');
      return;
    }
    SensorEngine.get().start();
    cancelSimRef.current?.();
    makeRig();
    wireEngine();
    setOutcome(null);
    setSession('live');
    setMessage('Reading ambient light... now throw it somewhere DARK.');
  };

  const startSim = () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    cancelSimRef.current?.();
    makeRig();
    setOutcome(null);
    setSession('sim');
    setMessage('Simulating a throw through a pitch black tunnel...');
    cancelSimRef.current = simulateEclipseThrow({
      imu: (s) => trackerRef.current?.feed(s),
      lux: handleLux,
      done: () => setSession((cur) => (cur === 'sim' ? null : cur)),
    });
  };

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-10">
      <Link href="/" className="text-sm text-zinc-400">
        ← Back to the lineup
      </Link>
      <h1 className="mt-2 text-3xl font-black">Eclipse 🌒</h1>
      <p className="mt-1 text-sm text-zinc-400">
        The light sensor rides along. Throw through darkness and score the dip. Under 2 lux
        mid-flight in a bright room = Total Eclipse.
      </p>

      {noLux && (
        <div className="mt-4 rounded-2xl border border-amber-400/40 bg-amber-400/10 p-3 text-xs text-amber-200">
          No ambient light sensor API here (Android Chrome, sometimes behind a flag). Use the
          simulator to see the show.
        </div>
      )}

      <section className="mt-4 rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
        <div className="flex items-baseline justify-between">
          <span className="text-sm font-bold text-zinc-300">Ambient light</span>
          <span className="font-mono text-2xl font-black text-amber-400">{lux.toFixed(0)} lux</span>
        </div>
        <div className="mt-3 h-4 overflow-hidden rounded-full bg-zinc-800">
          <div
            className="h-full bg-gradient-to-r from-zinc-500 via-amber-300 to-yellow-200 transition-all duration-150"
            style={{ width: `${Math.min(100, (lux / Math.max(200, baseline * 1.5)) * 100)}%` }}
          />
        </div>
        <div className="mt-2 text-xs text-zinc-500">baseline {baseline.toFixed(0)} lux</div>
      </section>

      <p className="mt-4 min-h-10 text-sm text-zinc-300">{message}</p>

      <div className="mt-4 space-y-3">
        <button
          onClick={startLive}
          className="w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
        >
          {session === 'live' ? 'REARM SENSORS 🌒' : 'CHASE THE DARK 🌒'}
        </button>
        <button
          onClick={startSim}
          className="w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold active:scale-95"
        >
          Simulate a blackout throw 🖥️
        </button>
      </div>

      {outcome && (
        <section
          className={`mt-6 rounded-2xl border p-4 ${
            outcome.verdict.fullBlackout
              ? 'border-amber-400/60 bg-amber-400/10'
              : 'border-zinc-700 bg-zinc-900'
          }`}
        >
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-black">
              {outcome.verdict.fullBlackout ? 'TOTAL ECLIPSE 🌑' : 'Flight report 🌗'}
            </h2>
            <span className="text-2xl font-black text-amber-400">{outcome.result.score}</span>
          </div>
          <div className="mt-1 text-xs text-zinc-400">Lux over the flight</div>
          <LuxChart outcome={outcome} />
          <div className="mt-2 grid grid-cols-3 gap-2 text-center text-sm">
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Min lux</div>
              <div className="font-bold">{outcome.verdict.minLux.toFixed(1)}</div>
            </div>
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Darkness dip</div>
              <div className="font-bold">{Math.round(outcome.verdict.dipRatio * 100)}%</div>
            </div>
            <div className="rounded-xl bg-zinc-800/70 p-2">
              <div className="text-xs text-zinc-500">Dark bonus</div>
              <div className="font-bold">+{outcome.verdict.bonus}</div>
            </div>
          </div>
          <div className="mt-2 text-xs text-zinc-500">
            {outcome.result.trickName} while eclipsed. {outcome.verdict.samples} light samples in
            flight.
          </div>
        </section>
      )}

      <p className="mt-6 text-xs text-zinc-600">
        Build a towel tunnel between two chairs. Dark, soft, scientific. The towel provides.
      </p>
    </main>
  );
}
