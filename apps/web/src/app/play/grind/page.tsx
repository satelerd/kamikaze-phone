'use client';

// Rail Grind: calibrate the magnetometer away from metal, then slide the phone
// along a steel rail. Mag deviation + sliding motion = grind; FXEngine turns it
// into rumble, torch flicker and a grind loop.
import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { award } from '@/lib/achievements';
import { AudioBus } from '@/lib/audio';
import { detectCapabilities } from '@/lib/capabilities';
import { FXEngine } from '@/lib/fx';
import { SensorEngine } from '@/lib/sensors';
import { speak } from '@/lib/speech';
import { GrindTracker, type GrindPhase, type GrindResult } from '@/modes/grind/logic';
import { simulateGrindSession } from '@/modes/grind/sim';

type Session = 'live' | 'sim' | null;

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
        // wake lock unavailable: no big deal
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

const PHASE_LABEL: Record<GrindPhase, string> = {
  idle: 'Waiting',
  calibrating: 'Calibrating baseline...',
  ready: 'Ready. Find the steel!',
  grinding: 'GRINDING 🔥',
};

export default function GrindPage() {
  const [session, setSession] = useState<Session>(null);
  const [phase, setPhase] = useState<GrindPhase>('idle');
  const [mag, setMag] = useState(0);
  const [delta, setDelta] = useState(0);
  const [baseline, setBaseline] = useState(0);
  const [intensity, setIntensity] = useState(0);
  const [last, setLast] = useState<GrindResult | null>(null);
  const [best, setBest] = useState(0);
  const [grinds, setGrinds] = useState(0);
  const [message, setMessage] = useState('Find some metal: handrails, bed frames, the good stuff.');
  const [noMag, setNoMag] = useState(false);

  const trackerRef = useRef<GrindTracker | null>(null);
  const unsubsRef = useRef<(() => void)[]>([]);
  const cancelSimRef = useRef<(() => void) | null>(null);

  useWakeLock(session !== null);

  useEffect(() => {
    setNoMag(detectCapabilities().magnetometer !== 'yes');
    const unsubs = unsubsRef.current;
    return () => {
      trackerRef.current?.finish();
      unsubs.forEach((u) => u());
      unsubs.length = 0;
      cancelSimRef.current?.();
    };
  }, []);

  const makeTracker = () =>
    new GrindTracker({
      onPhase: setPhase,
      onCalibrated: (b) => {
        setBaseline(b);
        setMessage('Calibrated! Slide it down the rail, nice and steady.');
        speak('Baseline locked. Go find that steel, dude!', { style: 'surfer' });
      },
      onLive: (m, d) => {
        setMag(m);
        setDelta(d);
      },
      onStart: () => {
        FXEngine.handle({ type: 'grind-start' });
        setMessage('GRINDING! Hold that line!');
      },
      onTick: (i) => {
        setIntensity(i);
        FXEngine.handle({ type: 'grind-tick', intensity: i });
      },
      onEnd: (result, durationMs) => {
        FXEngine.handle({ type: 'grind-end', ms: durationMs });
        setIntensity(0);
        if (!result) {
          setMessage('Too short! Kiss the rail a little longer next time.');
          return;
        }
        setLast(result);
        setGrinds((n) => n + 1);
        setBest((b) => Math.max(b, result.points));
        setMessage(`${(result.durationMs / 1000).toFixed(2)}s grind for ${result.points} points!`);
        award('first-spark');
        if (result.durationMs >= 2000) award('rail-lord');
        if (result.points >= 80) speak('That grind was buttery smooth, my dude!', { style: 'surfer' });
      },
    });

  const wireEngine = () => {
    if (unsubsRef.current.length) return;
    const eng = SensorEngine.get();
    unsubsRef.current.push(eng.onIMU((s) => trackerRef.current?.feedIMU(s)));
    unsubsRef.current.push(eng.onMag((s) => trackerRef.current?.feedMag(s)));
  };

  const startLive = async () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    const ok = await SensorEngine.get().requestPermission();
    if (!ok) {
      setMessage('Motion permission denied. No sensors, no grind.');
      return;
    }
    SensorEngine.get().start();
    cancelSimRef.current?.();
    trackerRef.current = makeTracker();
    wireEngine();
    trackerRef.current.beginCalibration();
    setLast(null);
    setSession('live');
    setMessage('Hold the phone away from metal while it learns the room...');
  };

  const startSim = () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    cancelSimRef.current?.();
    trackerRef.current = makeTracker();
    trackerRef.current.beginCalibration();
    setLast(null);
    setSession('sim');
    setMessage('Simulating: calibration, then a 2.6 second wobbly rail...');
    cancelSimRef.current = simulateGrindSession({
      imu: (s) => trackerRef.current?.feedIMU(s),
      mag: (s) => trackerRef.current?.feedMag(s),
      done: () => setSession((cur) => (cur === 'sim' ? null : cur)),
    });
  };

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-10">
      <Link href="/" className="text-sm text-zinc-400">
        ← Back to the lineup
      </Link>
      <h1 className="mt-2 text-3xl font-black">Rail Grind 🛹</h1>
      <p className="mt-1 text-sm text-zinc-400">
        Calibrate away from metal, then slide the phone along a steel rail. The magnetometer feels
        every centimeter. Score = duration x steadiness.
      </p>

      {noMag && (
        <div className="mt-4 rounded-2xl border border-amber-400/40 bg-amber-400/10 p-3 text-xs text-amber-200">
          No magnetometer API on this rig (Android Chrome only). Use the simulator button to feel
          the vibe anyway.
        </div>
      )}

      <div className="mt-4 flex items-center gap-2">
        <span
          className={`rounded-full px-3 py-1 text-xs font-bold ${
            phase === 'grinding'
              ? 'bg-amber-400 text-zinc-950'
              : phase === 'ready'
                ? 'bg-emerald-400/20 text-emerald-300'
                : 'bg-zinc-800 text-zinc-300'
          }`}
        >
          {PHASE_LABEL[phase]}
        </span>
        {session === 'sim' && <span className="text-xs text-zinc-500">simulator running</span>}
      </div>

      <section className="mt-4 rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
        <div className="flex items-baseline justify-between">
          <span className="text-sm font-bold text-zinc-300">Field strength</span>
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
        {phase === 'grinding' && (
          <div className="mt-3">
            <div className="text-xs text-zinc-400">Grind intensity</div>
            <div className="mt-1 h-2 overflow-hidden rounded-full bg-zinc-800">
              <div className="h-full bg-emerald-400" style={{ width: `${intensity * 100}%` }} />
            </div>
          </div>
        )}
      </section>

      <p className="mt-4 min-h-10 text-sm text-zinc-300">{message}</p>

      <div className="mt-4 space-y-3">
        <button
          onClick={startLive}
          className="w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
        >
          {session === 'live' ? 'RECALIBRATE 🧭' : 'START GRINDING 🧭'}
        </button>
        <button
          onClick={startSim}
          className="w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold active:scale-95"
        >
          Simulate a grind 🖥️
        </button>
      </div>

      {last && (
        <section className="mt-6 rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
          <h2 className="text-sm font-bold text-zinc-300">Last grind</h2>
          <div className="mt-2 grid grid-cols-2 gap-2 text-sm">
            <div className="rounded-xl bg-zinc-800/70 p-3">
              <div className="text-xs text-zinc-500">Duration</div>
              <div className="text-xl font-black">{(last.durationMs / 1000).toFixed(2)}s</div>
            </div>
            <div className="rounded-xl bg-zinc-800/70 p-3">
              <div className="text-xs text-zinc-500">Steadiness</div>
              <div className="text-xl font-black">{Math.round(last.steadiness * 100)}%</div>
            </div>
            <div className="rounded-xl bg-zinc-800/70 p-3">
              <div className="text-xs text-zinc-500">Peak delta</div>
              <div className="text-xl font-black">{last.peakDelta.toFixed(0)} µT</div>
            </div>
            <div className="rounded-xl bg-amber-400/10 p-3">
              <div className="text-xs text-amber-300">Points</div>
              <div className="text-xl font-black text-amber-400">{last.points}</div>
            </div>
          </div>
          <div className="mt-3 flex justify-between text-xs text-zinc-500">
            <span>session grinds: {grinds}</span>
            <span>best: {best} pts</span>
          </div>
        </section>
      )}

      <p className="mt-6 text-xs text-zinc-600">
        Pro tip: a 2 second grind earns the Rail Lord badge. Fridges count as rails. We do not judge.
      </p>
    </main>
  );
}
