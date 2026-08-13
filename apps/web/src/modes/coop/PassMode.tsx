'use client';

// Single-phone fallback: riders A and B alternate throws on the same phone.
// Coordination = how closely B matches A's airtime and trick. Same scoring UI.
import { useCallback, useRef, useState } from 'react';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import { classifyThrow } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { recordTrick } from '@/lib/store';
import Countdown from './Countdown';
import SyncResult from './SyncResult';
import TrickCard from './TrickCard';
import {
  COUNTDOWN_LEAD_MS,
  celebrateSync,
  computeSync,
  landEpochOf,
  launchEpochOf,
  riderFromResult,
} from './sync';
import type { RiderThrow, SyncBreakdown } from './sync';
import { useThrowCapture } from './useThrowCapture';
import { useWakeLock } from './useWakeLock';

type Stage =
  | { st: 'intro' }
  | { st: 'count'; rider: 'a' | 'b'; startAt: number }
  | { st: 'air'; rider: 'a' | 'b' }
  | { st: 'handoff' }
  | { st: 'result'; bd: SyncBreakdown; best: number; isNewBest: boolean };

export default function PassMode({ playerName }: { playerName: string }) {
  const nameA = playerName || 'Rider A';
  const nameB = 'Rider B';
  const [stage, setStage] = useState<Stage>({ st: 'intro' });
  const stageRef = useRef(stage);
  stageRef.current = stage;
  const [a, setA] = useState<RiderThrow | null>(null);
  const aRef = useRef<RiderThrow | null>(null);
  const [b, setB] = useState<RiderThrow | null>(null);

  useWakeLock(stage.st !== 'intro');

  const { arm } = useThrowCapture((rec) => {
    const cur = stageRef.current;
    if (cur.st !== 'air') return;
    const result = classifyThrow(rec, 'coop');
    recordTrick(result);
    FXEngine.handle({ type: 'trick', result });
    const rider = riderFromResult(
      result,
      launchEpochOf(rec),
      landEpochOf(rec),
      cur.rider === 'a' ? nameA : nameB,
    );
    if (cur.rider === 'a') {
      setA(rider);
      aRef.current = rider;
      setStage({ st: 'handoff' });
    } else {
      setB(rider);
      const first = aRef.current;
      if (first) {
        const bd = computeSync(first, rider, 'pass');
        const saved = celebrateSync(bd);
        setStage({ st: 'result', bd, ...saved });
      }
    }
  });

  const startRun = useCallback(async () => {
    // user gesture: unlock audio + motion before the first countdown
    AudioBus.ensure();
    const engine = SensorEngine.get();
    const ok = await engine.requestPermission();
    if (ok) engine.start();
    FXEngine.handle({ type: 'ui-start' });
    setA(null);
    aRef.current = null;
    setB(null);
    setStage({ st: 'count', rider: 'a', startAt: Date.now() + COUNTDOWN_LEAD_MS });
  }, []);

  const riderBReady = useCallback(() => {
    FXEngine.handle({ type: 'ui-select' });
    setStage({ st: 'count', rider: 'b', startAt: Date.now() + COUNTDOWN_LEAD_MS });
  }, []);

  const onGo = useCallback(() => {
    const cur = stageRef.current;
    if (cur.st !== 'count') return;
    FXEngine.handle({ type: 'ui-start' });
    arm();
    setStage({ st: 'air', rider: cur.rider });
  }, [arm]);

  return (
    <div className="space-y-4">
      {stage.st === 'intro' && (
        <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-5">
          <div className="text-lg font-black">One phone, two riders 🔁</div>
          <p className="mt-2 text-sm text-zinc-400">
            {nameA} sets the line. Then hand the phone over and {nameB} matches the airtime and the
            trick. Closest echo wins the sync.
          </p>
          <button
            onClick={() => void startRun()}
            className="mt-4 w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
          >
            RIDER A UP 🅰️
          </button>
        </div>
      )}

      {stage.st === 'count' && (
        <Countdown
          startAt={stage.startAt}
          onGo={onGo}
          subtitle={`${stage.rider === 'a' ? nameA : nameB} on deck`}
          hint={stage.rider === 'a' ? 'Set the line. SEND IT on zero.' : 'Match that throw. SEND IT on zero.'}
        />
      )}

      {stage.st === 'air' && (
        <div className="rounded-2xl border border-amber-400/60 bg-zinc-900 p-8 text-center">
          <div className="text-5xl font-black text-amber-400">SEND IT! 🚀</div>
          <p className="mt-2 text-sm text-zinc-400">
            {stage.rider === 'a' ? nameA : nameB}, throw NOW. Land it clean.
          </p>
        </div>
      )}

      {stage.st === 'handoff' && a && (
        <div className="space-y-4">
          <TrickCard rider={a} label={`${nameA} set the line`} />
          <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-5 text-center">
            <div className="text-3xl">🤝📱</div>
            <div className="mt-2 text-lg font-black">Pass the phone!</div>
            <p className="mt-1 text-sm text-zinc-400">
              {nameB}: match {a.airtime.toFixed(2)}s of {a.trickName}.
            </p>
            <button
              onClick={riderBReady}
              className="mt-4 w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
            >
              RIDER B READY 🅱️
            </button>
          </div>
        </div>
      )}

      {stage.st === 'result' && a && b && (
        <>
          <div className="grid grid-cols-2 gap-3">
            <TrickCard rider={a} label={nameA} />
            <TrickCard rider={b} label={nameB} />
          </div>
          <SyncResult bd={stage.bd} best={stage.best} isNewBest={stage.isNewBest}>
            <button
              onClick={() => void startRun()}
              className="w-full rounded-xl bg-amber-400 px-4 py-3 font-black text-zinc-950 active:scale-95"
            >
              RUN IT BACK 🔁
            </button>
          </SyncResult>
        </>
      )}
    </div>
  );
}
