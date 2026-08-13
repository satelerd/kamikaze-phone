'use client';

// Hot Potato setup: crew size (2-10), editable names, fuse range, pass order.
import { useState } from 'react';
import { FXEngine } from '@/lib/fx';
import type { FusePresetId, HotPotatoConfig, PassOrder } from './types';
import { FUSE_PRESETS, MAX_PLAYERS, MIN_PLAYERS } from './types';

const ORDER_OPTIONS: { id: PassOrder; label: string; emoji: string; blurb: string }[] = [
  {
    id: 'circle',
    label: 'Circle',
    emoji: '🔄',
    blurb: 'The spud goes around the ring in order.',
  },
  {
    id: 'chaos',
    label: 'Chaos',
    emoji: '🎲',
    blurb: 'Anyone can catch it. Total mayhem.',
  },
];

export default function SetupScreen({ onStart }: { onStart: (cfg: HotPotatoConfig) => void }) {
  const [names, setNames] = useState<string[]>(['Player 1', 'Player 2', 'Player 3']);
  const [fuse, setFuse] = useState<FusePresetId>('normal');
  const [order, setOrder] = useState<PassOrder>('circle');

  const addPlayer = () => {
    if (names.length >= MAX_PLAYERS) return;
    setNames([...names, `Player ${names.length + 1}`]);
    FXEngine.handle({ type: 'ui-select' });
  };

  const removePlayer = () => {
    if (names.length <= MIN_PLAYERS) return;
    setNames(names.slice(0, -1));
    FXEngine.handle({ type: 'ui-select' });
  };

  const renameAt = (i: number, value: string) => {
    setNames(names.map((n, idx) => (idx === i ? value : n)));
  };

  const start = () => {
    const cleaned = names.map((n, i) => n.trim() || `Player ${i + 1}`);
    onStart({ names: cleaned, fuse, order });
  };

  return (
    <div>
      <h1 className="text-3xl font-black">Hot Potato 🥔</h1>
      <p className="mt-1 text-zinc-400">Pass it before it blows. Last rider standing wins.</p>

      <section className="mt-6">
        <p className="text-sm font-bold text-zinc-300">Who is in the circle?</p>
        <div className="mt-2 flex items-center gap-4">
          <button
            onClick={removePlayer}
            disabled={names.length <= MIN_PLAYERS}
            className="h-12 w-12 rounded-xl border border-zinc-700 bg-zinc-900 text-2xl font-black active:scale-95 disabled:opacity-30"
            aria-label="Remove a player"
          >
            −
          </button>
          <span className="w-16 text-center text-3xl font-black text-amber-400">{names.length}</span>
          <button
            onClick={addPlayer}
            disabled={names.length >= MAX_PLAYERS}
            className="h-12 w-12 rounded-xl border border-zinc-700 bg-zinc-900 text-2xl font-black active:scale-95 disabled:opacity-30"
            aria-label="Add a player"
          >
            +
          </button>
          <span className="text-sm text-zinc-500">2 to 10 players</span>
        </div>
        <div className="mt-3 space-y-2">
          {names.map((n, i) => (
            <input
              key={i}
              value={n}
              onChange={(e) => renameAt(i, e.target.value)}
              placeholder={`Player ${i + 1}`}
              className="w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 outline-none focus:border-amber-400"
            />
          ))}
        </div>
      </section>

      <section className="mt-6">
        <p className="text-sm font-bold text-zinc-300">How long does the fuse burn?</p>
        <p className="text-xs text-zinc-500">The exact length is random and secret. Sorry not sorry.</p>
        <div className="mt-2 grid grid-cols-1 gap-3">
          {FUSE_PRESETS.map((p) => (
            <button
              key={p.id}
              onClick={() => {
                setFuse(p.id);
                FXEngine.handle({ type: 'ui-select' });
              }}
              className={`rounded-2xl border p-4 text-left ${
                fuse === p.id ? 'border-amber-400 bg-amber-400/10' : 'border-zinc-700 bg-zinc-900'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="font-bold">
                  {p.emoji} {p.label}
                </span>
                <span className="text-sm text-zinc-400">
                  {p.min / 1000} to {p.max / 1000}s
                </span>
              </div>
              <div className="mt-1 text-xs text-zinc-400">{p.blurb}</div>
            </button>
          ))}
        </div>
      </section>

      <section className="mt-6">
        <p className="text-sm font-bold text-zinc-300">Pass order</p>
        <div className="mt-2 grid grid-cols-2 gap-3">
          {ORDER_OPTIONS.map((o) => (
            <button
              key={o.id}
              onClick={() => {
                setOrder(o.id);
                FXEngine.handle({ type: 'ui-select' });
              }}
              className={`rounded-2xl border p-4 text-left ${
                order === o.id ? 'border-amber-400 bg-amber-400/10' : 'border-zinc-700 bg-zinc-900'
              }`}
            >
              <div className="font-bold">
                {o.emoji} {o.label}
              </div>
              <div className="mt-1 text-xs text-zinc-400">{o.blurb}</div>
            </button>
          ))}
        </div>
      </section>

      <button
        onClick={start}
        className="mt-8 w-full rounded-2xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
      >
        GRAB THE TOWEL 🧻
      </button>
    </div>
  );
}
