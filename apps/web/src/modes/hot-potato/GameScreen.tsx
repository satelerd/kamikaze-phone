'use client';

// Hot Potato game loop: hidden random fuse, exponentially accelerating tick,
// throw/catch detection from the shared ThrowTracker, name narration via
// speak(), elimination rounds until one rider remains.
import { useEffect, useRef, useState } from 'react';
import { AudioBus } from '@/lib/audio';
import { detectCapabilities } from '@/lib/capabilities';
import { FXEngine } from '@/lib/fx';
import { ThrowTracker } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { generateThrow } from '@/lib/sim';
import { speak } from '@/lib/speech';
import { getState } from '@/lib/store';
import type { GameEvent } from '@/lib/types';
import { airborneLine, boomLine, catchLine, dropLine, roundLine } from './lines';
import type { HotPotatoConfig } from './types';
import { FUSE_PRESETS, TICK_END_MS, TICK_START_MS } from './types';

interface PlayerState {
  name: string;
  alive: boolean;
}

type RoundStage = 'intro' | 'live' | 'boom' | 'round-over';

interface GameScreenProps {
  config: HotPotatoConfig;
  onWinner: (name: string) => void;
  onQuit: () => void;
}

export default function GameScreen({ config, onWinner, onQuit }: GameScreenProps) {
  const [players, setPlayers] = useState<PlayerState[]>(() =>
    config.names.map((name) => ({ name, alive: true })),
  );
  const [holder, setHolder] = useState(0);
  const [round, setRound] = useState(1);
  const [flying, setFlying] = useState(false);
  const [tickMs, setTickMs] = useState<number>(TICK_START_MS);
  const [stage, setStage] = useState<RoundStage>('intro');
  const [boomFlash, setBoomFlash] = useState(false);
  const [lastOut, setLastOut] = useState<string | null>(null);
  const [simBusy, setSimBusy] = useState(false);
  const [hasRealMotion] = useState(() => detectCapabilities().motion !== 'no');

  // Refs mirror the loop state so timer/sensor callbacks never go stale.
  const playersRef = useRef(players);
  const holderRef = useRef(0);
  const stageRef = useRef<RoundStage>('intro');
  const roundRef = useRef(1);
  const fuseStartRef = useRef(0);
  const fuseMsRef = useRef(0);
  const countdownNRef = useRef(99);
  const timersRef = useRef<ReturnType<typeof setTimeout>[]>([]);
  const lastAirCallRef = useRef(0);
  const simBusyRef = useRef(false);

  function later(fn: () => void, ms: number): void {
    timersRef.current.push(setTimeout(fn, ms));
  }

  function clearTimers(): void {
    timersRef.current.forEach(clearTimeout);
    timersRef.current = [];
  }

  function setHolderBoth(i: number): void {
    holderRef.current = i;
    setHolder(i);
  }

  function setStageBoth(s: RoundStage): void {
    stageRef.current = s;
    setStage(s);
  }

  function aliveIndices(): number[] {
    return playersRef.current.map((p, i) => (p.alive ? i : -1)).filter((i) => i >= 0);
  }

  // ------------------------------------------------------------------
  // Round lifecycle
  // ------------------------------------------------------------------
  function startRound(starterIdx: number): void {
    clearTimers();
    setFlying(false);
    setTickMs(TICK_START_MS);
    countdownNRef.current = 99;
    setHolderBoth(starterIdx);
    setStageBoth('intro');
    const preset = FUSE_PRESETS.find((f) => f.id === config.fuse) ?? FUSE_PRESETS[1];
    const fuseMs = preset.min + Math.random() * (preset.max - preset.min);
    speak(roundLine(roundRef.current, playersRef.current[starterIdx].name), {
      style: 'caller',
      forceLocal: true,
      interrupt: true,
    });
    later(() => {
      if (stageRef.current !== 'intro') return;
      setStageBoth('live');
      fuseStartRef.current = performance.now();
      fuseMsRef.current = fuseMs;
      later(explode, fuseMs);
      tick();
    }, 1800);
  }

  /** Accelerating tick: 600ms at ignition, exponential decay to 120ms at the end. */
  function tick(): void {
    if (stageRef.current !== 'live') return;
    const elapsed = performance.now() - fuseStartRef.current;
    const progress = Math.min(1, elapsed / fuseMsRef.current);
    const interval = TICK_START_MS * Math.pow(TICK_END_MS / TICK_START_MS, progress);
    setTickMs(interval);
    void AudioBus.play('potato-tick');
    const remaining = fuseMsRef.current - elapsed;
    const n = Math.ceil(remaining / 1000);
    if (remaining <= 3300 && n >= 1 && n < countdownNRef.current) {
      countdownNRef.current = n;
      FXEngine.handle({ type: 'countdown-tick', n });
    }
    later(tick, interval);
  }

  function explode(): void {
    if (stageRef.current !== 'live') return;
    clearTimers();
    setStageBoth('boom');
    setFlying(false);
    setBoomFlash(true);
    void AudioBus.play('potato-boom');
    if (getState().settings.hapticsEnabled && typeof navigator !== 'undefined' && 'vibrate' in navigator) {
      try {
        navigator.vibrate([400, 100, 400]);
      } catch {
        // no haptics on this device
      }
    }
    later(() => setBoomFlash(false), 650);

    const victimIdx = holderRef.current;
    const victim = playersRef.current[victimIdx];
    const nextPlayers = playersRef.current.map((p, i) =>
      i === victimIdx ? { ...p, alive: false } : p,
    );
    playersRef.current = nextPlayers;
    setPlayers(nextPlayers);
    setLastOut(victim.name);

    later(() => {
      void AudioBus.play('crowd-oooh');
      speak(boomLine(victim.name), { style: 'caller', forceLocal: true, interrupt: true });
    }, 500);

    const survivors = nextPlayers.filter((p) => p.alive);
    later(() => {
      if (survivors.length <= 1) onWinner(survivors[0]?.name ?? victim.name);
      else setStageBoth('round-over');
    }, 2000);
  }

  function nextRound(): void {
    roundRef.current += 1;
    setRound(roundRef.current);
    const alive = aliveIndices();
    const starter = alive[Math.floor(Math.random() * alive.length)];
    FXEngine.handle({ type: 'ui-start' });
    startRound(starter);
  }

  // ------------------------------------------------------------------
  // Throw detection
  // ------------------------------------------------------------------
  function pickNextHolder(): number | null {
    const alive = aliveIndices();
    if (alive.length <= 1) return null;
    const cur = holderRef.current;
    if (config.order === 'circle') {
      const pos = alive.indexOf(cur);
      return alive[(pos + 1) % alive.length];
    }
    const others = alive.filter((i) => i !== cur);
    return others[Math.floor(Math.random() * others.length)];
  }

  function handleThrowEvent(e: GameEvent): void {
    if (stageRef.current !== 'live') {
      if (e.type === 'catch') setFlying(false);
      return;
    }
    if (e.type === 'launch') {
      setFlying(true);
      FXEngine.handle(e);
      const now = performance.now();
      if (now - lastAirCallRef.current > 7000 && Math.random() < 0.5) {
        lastAirCallRef.current = now;
        speak(airborneLine(), { style: 'caller', forceLocal: true });
      }
    } else if (e.type === 'flip') {
      FXEngine.handle(e);
    } else if (e.type === 'catch') {
      setFlying(false);
      FXEngine.handle(e);
      const holderName = playersRef.current[holderRef.current].name;
      if (!e.clean) {
        // Drop: instant roast, potato stays with the same holder.
        speak(dropLine(holderName), { style: 'caller', forceLocal: true, interrupt: true });
        return;
      }
      const next = pickNextHolder();
      if (next === null) return;
      setHolderBoth(next);
      speak(catchLine(playersRef.current[next].name), {
        style: 'caller',
        forceLocal: true,
        interrupt: true,
      });
    }
  }

  useEffect(() => {
    const engine = SensorEngine.get();
    engine.start(); // idempotent; permission was granted at the towel screen
    const tracker = new ThrowTracker(() => {}, handleThrowEvent);
    const unsub = engine.onIMU((s) => tracker.feed(s));
    startRound(Math.floor(Math.random() * config.names.length));
    return () => {
      unsub();
      clearTimers();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Wake lock: the screen must not sleep mid-round. Re-acquire on tab return.
  useEffect(() => {
    let lock: WakeLockSentinel | null = null;
    let done = false;
    const acquire = async () => {
      if (done || typeof navigator === 'undefined' || !('wakeLock' in navigator)) return;
      try {
        lock = await navigator.wakeLock.request('screen');
      } catch {
        lock = null; // low battery or unsupported: play on
      }
    };
    const onVis = () => {
      if (document.visibilityState === 'visible') void acquire();
    };
    void acquire();
    document.addEventListener('visibilitychange', onVis);
    return () => {
      done = true;
      document.removeEventListener('visibilitychange', onVis);
      void lock?.release().catch(() => {});
    };
  }, []);

  // ------------------------------------------------------------------
  // Desktop demo: inject a synthetic throw through the real pipeline.
  // ------------------------------------------------------------------
  async function simulatePass(): Promise<void> {
    if (simBusyRef.current || stageRef.current !== 'live') return;
    simBusyRef.current = true;
    setSimBusy(true);
    const samples = generateThrow({
      airtime: 0.5 + Math.random() * 0.45,
      spinsX: 1 + Math.floor(Math.random() * 2),
      clean: Math.random() > 0.18,
      impactG: 40 + Math.random() * 30,
      leadInMs: 150,
    });
    await SensorEngine.get().injectSamples(samples, true);
    simBusyRef.current = false;
    setSimBusy(false);
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------
  const holderName = players[holder]?.name ?? '';
  const aliveCount = players.filter((p) => p.alive).length;
  const shakePx =
    2 + (1 - (tickMs - TICK_END_MS) / (TICK_START_MS - TICK_END_MS)) * 9;
  const potatoStyle: React.CSSProperties = flying
    ? { animation: 'hp-float 900ms ease-in-out infinite' }
    : ({
        animation: `hp-shake ${Math.max(TICK_END_MS, Math.round(tickMs))}ms linear infinite`,
        '--shake': `${shakePx.toFixed(1)}px`,
      } as React.CSSProperties);

  const roster = (
    <div className="flex flex-wrap justify-center gap-2">
      {players.map((p, i) => (
        <span
          key={`${p.name}-${i}`}
          className={`rounded-full border px-3 py-1 text-sm font-semibold ${
            !p.alive
              ? 'border-zinc-800 bg-zinc-900/50 text-zinc-600'
              : i === holder
                ? 'border-amber-400 bg-amber-400/10 text-amber-300'
                : 'border-zinc-700 bg-zinc-900 text-zinc-300'
          }`}
        >
          {p.alive ? p.name : <><s>{p.name}</s> 🪦</>}
        </span>
      ))}
    </div>
  );

  return (
    <div className="relative">
      {/* Red explosion flash, this mode's own (FX torch flash is white) */}
      <div
        aria-hidden
        className={`pointer-events-none fixed inset-0 z-[90] bg-red-600 transition-opacity duration-150 ${
          boomFlash ? 'opacity-80' : 'opacity-0'
        }`}
      />

      <div className="flex items-center justify-between">
        <span className="rounded-full border border-zinc-700 bg-zinc-900 px-3 py-1 text-sm font-bold">
          Round {round}
        </span>
        <span
          className={`rounded-full px-3 py-1 text-sm font-black ${
            flying
              ? 'bg-amber-400 text-zinc-950'
              : 'border border-zinc-700 bg-zinc-900 text-zinc-300'
          }`}
        >
          {flying ? 'FLYING 💨' : 'IN HANDS ✋'}
        </span>
        <button
          onClick={onQuit}
          className="rounded-full border border-zinc-700 bg-zinc-900 px-3 py-1 text-sm text-zinc-400 active:scale-95"
        >
          Bail
        </button>
      </div>

      <div className="mt-10 flex flex-col items-center">
        <span className="select-none text-8xl" style={potatoStyle}>
          🥔
        </span>
        <p className="mt-6 text-xs uppercase tracking-widest text-zinc-500">
          {flying ? 'Spud in flight! Thrown by' : 'Holding the spud'}
        </p>
        <h2 className="mt-1 break-words text-center text-5xl font-black text-amber-400">
          {holderName}
        </h2>
        <p className="mt-3 text-sm text-zinc-500">Fuse length is a mystery. Pass it fast.</p>
      </div>

      <div className="mt-10">{roster}</div>

      <div className="mt-10 flex justify-center">
        <button
          onClick={() => void simulatePass()}
          disabled={simBusy || stage !== 'live'}
          className={
            hasRealMotion
              ? 'text-xs text-zinc-600 underline underline-offset-2 disabled:opacity-40'
              : 'w-full max-w-xs rounded-2xl border border-amber-400/50 bg-zinc-900 px-4 py-3 font-bold text-amber-300 active:scale-95 disabled:opacity-40'
          }
        >
          {simBusy ? 'Spud in flight...' : 'Simulate pass 🖥️'}
        </button>
      </div>

      {stage === 'intro' && (
        <div className="fixed inset-0 z-40 flex flex-col items-center justify-center bg-zinc-950/95 px-6">
          <p className="text-sm uppercase tracking-widest text-zinc-500">Round {round}</p>
          <h2 className="mt-2 break-words text-center text-4xl font-black">
            {holderName} starts 🥔
          </h2>
          <p className="mt-3 text-zinc-400">Fuse is lit. Length unknown. Good luck.</p>
        </div>
      )}

      {stage === 'round-over' && (
        <div className="fixed inset-0 z-40 flex flex-col items-center justify-center bg-zinc-950/95 px-6">
          <span className="text-7xl">💥</span>
          <h2 className="mt-4 break-words text-center text-4xl font-black text-red-400">
            {lastOut} got roasted
          </h2>
          <p className="mt-2 text-zinc-400">{aliveCount} riders still standing</p>
          <div className="mt-6">{roster}</div>
          <button
            onClick={nextRound}
            className="mt-8 w-full max-w-xs rounded-2xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
          >
            NEXT ROUND 🔥
          </button>
          <button onClick={onQuit} className="mt-3 text-sm text-zinc-500">
            Everybody bails
          </button>
        </div>
      )}

      <style>{`
        @keyframes hp-shake {
          0% { transform: translate(0, 0) rotate(0deg); }
          25% { transform: translate(var(--shake, 3px), calc(var(--shake, 3px) * -1)) rotate(-7deg); }
          50% { transform: translate(calc(var(--shake, 3px) * -1), var(--shake, 3px)) rotate(6deg); }
          75% { transform: translate(var(--shake, 3px), var(--shake, 3px)) rotate(-5deg); }
          100% { transform: translate(0, 0) rotate(0deg); }
        }
        @keyframes hp-float {
          0%, 100% { transform: translateY(0) rotate(-8deg); }
          50% { transform: translateY(-18px) rotate(8deg); }
        }
      `}</style>
    </div>
  );
}
