'use client';

// Desktop demo: two synthetic riders through the FULL scoring path.
// Rider One is injected into the real SensorEngine stream (live ThrowTracker),
// Rider Two arrives as a faked remote 'throw' message parsed by the same
// adapter the two-phone mode uses.
import { useCallback, useRef, useState } from 'react';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import type { ThrowMessage } from '@/lib/peer';
import { classifyThrow } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { generateThrow, resetSimSeed } from '@/lib/sim';
import type { SimThrowParams } from '@/lib/sim';
import { recordTrick } from '@/lib/store';
import SyncResult from './SyncResult';
import TrickCard from './TrickCard';
import {
  celebrateSync,
  classifySamples,
  computeSync,
  landEpochOf,
  launchEpochOf,
  riderFromResult,
  riderFromThrowMessage,
} from './sync';
import type { RiderThrow, SyncBreakdown } from './sync';
import { useThrowCapture } from './useThrowCapture';

interface Outcome {
  bd: SyncBreakdown;
  me: RiderThrow;
  them: RiderThrow;
  best: number;
  isNewBest: boolean;
}

const SPIN_OPTIONS: Array<Partial<Pick<SimThrowParams, 'spinsX' | 'spinsY' | 'spinsZ'>>> = [
  { spinsX: 2 },
  { spinsX: 1 },
  { spinsY: 2 },
  { spinsZ: 1.3 },
];

export default function SimMode() {
  const [busy, setBusy] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [error, setError] = useState<string | null>(null);
  const pendingRef = useRef<{ msgOf: (localLaunch: number) => ThrowMessage } | null>(null);

  const { arm } = useThrowCapture((rec) => {
    const pending = pendingRef.current;
    pendingRef.current = null;
    if (!pending) return;
    const result = classifyThrow(rec, 'coop');
    recordTrick(result);
    FXEngine.handle({ type: 'trick', result });
    const me = riderFromResult(result, launchEpochOf(rec), landEpochOf(rec), 'Rider One');
    // Rider Two comes in as a faked remote message; identity clock (offset 0).
    const msg = pending.msgOf(me.launchEpoch);
    const them = riderFromThrowMessage(msg, (t) => t, 'Rider Two');
    const bd = computeSync(me, them, 'linked');
    const saved = celebrateSync(bd);
    setOutcome({ bd, me, them, ...saved });
    setBusy(false);
  });

  const run = useCallback(async () => {
    if (busy) return;
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    setError(null);
    setOutcome(null);
    setBusy(true);

    const airtime = 0.7 + Math.random() * 0.5;
    const spin = SPIN_OPTIONS[Math.floor(Math.random() * SPIN_OPTIONS.length)];

    // Rider Two: a slightly-off echo of the same trick, classified offline.
    resetSimSeed(Math.floor(Math.random() * 1e9));
    const remoteAirtime = airtime * (1 + (Math.random() * 0.24 - 0.12));
    const remoteResult = classifySamples(generateThrow({ airtime: remoteAirtime, ...spin }));
    if (!remoteResult) {
      setError('Rider Two never left the ground. Run it again.');
      setBusy(false);
      return;
    }
    const jitterMs = Math.random() * 480 - 240;
    pendingRef.current = {
      msgOf: (localLaunch) => ({
        t: 'throw',
        launchT: localLaunch + jitterMs,
        landT: localLaunch + jitterMs + remoteResult.features.airtime * 1000,
        airtime: remoteResult.features.airtime,
        trickId: remoteResult.trickId,
        trickName: remoteResult.trickName,
        score: remoteResult.score,
        grade: remoteResult.grade,
      }),
    };

    // Rider One: injected into the real SensorEngine stream in realtime.
    resetSimSeed(Math.floor(Math.random() * 1e9));
    arm();
    await SensorEngine.get().injectSamples(generateThrow({ airtime, ...spin }), true);

    // The tracker should have fired mid-stream; if not, fail loud.
    if (pendingRef.current) {
      pendingRef.current = null;
      setError('Rider One bailed mid-sim. Run it again.');
      setBusy(false);
    }
  }, [arm, busy]);

  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-5">
        <div className="text-lg font-black">Simulate both riders 🖥️</div>
        <p className="mt-2 text-sm text-zinc-400">
          Desktop demo: two synthetic throws race through the full scoring path. One rides the real
          sensor engine, one lands as a remote message.
        </p>
        <button
          onClick={() => void run()}
          disabled={busy}
          className="mt-4 w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95 disabled:opacity-40"
        >
          {busy ? 'RIDERS AIRBORNE... 🛫' : outcome ? 'RUN IT AGAIN 🔁' : 'SIMULATE BOTH RIDERS 🚀'}
        </button>
        {error && <p className="mt-3 text-sm text-red-300">{error}</p>}
      </div>

      {outcome && (
        <>
          <div className="grid grid-cols-2 gap-3">
            <TrickCard rider={outcome.me} label="Rider One" />
            <TrickCard rider={outcome.them} label="Rider Two" />
          </div>
          <SyncResult bd={outcome.bd} best={outcome.best} isNewBest={outcome.isNewBest} />
        </>
      )}
    </div>
  );
}
