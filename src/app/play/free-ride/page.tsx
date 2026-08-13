'use client';

// Free Ride: the narrator showcase. Open session, every throw classified,
// scored, carded into the feed, and called live by Bodhi Bytes.
import { useEffect, useState } from 'react';
import Link from 'next/link';
import TrickCard from '@/components/TrickCard';
import { Narrator, type NarratorLine } from '@/lib/narrator';
import { useFreeRideSession, type UiPhase } from '@/modes/free-ride/useFreeRideSession';

const PHASE_UI: Record<UiPhase, { label: string; cls: string }> = {
  chilling: { label: '🧘 Chilling', cls: 'border-zinc-700 bg-zinc-900 text-zinc-400' },
  windup: { label: '💪 WINDUP', cls: 'border-amber-400/60 bg-amber-400/10 text-amber-300' },
  airborne: { label: '🌀 AIRBORNE', cls: 'border-sky-400/60 bg-sky-400/10 text-sky-300 animate-pulse' },
  caught: { label: '🙌 CAUGHT', cls: 'border-emerald-400/60 bg-emerald-400/10 text-emerald-300' },
};

export default function FreeRidePage() {
  const {
    running, permissionError, phase, flips, feed, stats, simulating, start, simulate,
  } = useFreeRideSession();
  const [caption, setCaption] = useState<NarratorLine | null>(null);

  useEffect(() => Narrator.subscribe(setCaption), []);

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-28 pt-8">
      <header className="flex items-center gap-3">
        <Link
          href="/"
          className="flex h-10 w-10 items-center justify-center rounded-xl border border-zinc-700 bg-zinc-900 text-lg"
          aria-label="Back to modes"
        >
          ←
        </Link>
        <div>
          <h1 className="text-2xl font-black">Free Ride 🌊</h1>
          <p className="text-xs text-zinc-400">Open session. Bodhi calls every throw.</p>
        </div>
      </header>

      {/* Narrator caption, front and center */}
      <section className="mt-4 flex min-h-[84px] items-center gap-3 rounded-2xl border border-amber-400/30 bg-amber-400/5 p-4">
        <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full border-2 border-amber-300/70 bg-gradient-to-br from-amber-400 to-amber-600 text-2xl">
          🏄
        </span>
        <p
          className={`text-sm leading-snug ${caption ? 'font-semibold text-amber-100' : 'italic text-zinc-500'}`}
          aria-live="polite"
        >
          {caption ? caption.text : 'Bodhi is watching. Wrap it in a towel and send it, brah.'}
        </p>
      </section>

      {!running && (
        <section className="mt-5 space-y-3">
          <button
            onClick={() => void start()}
            className="w-full rounded-2xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
          >
            START SESSION 🤙
          </button>
          {permissionError && (
            <p className="rounded-xl border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-300">
              Motion sensors got denied, brah. Check the browser permission and try again.
            </p>
          )}
          <p className="text-center text-xs text-zinc-500">
            🧻 Towel gospel: wrap the phone, clear the ceiling fan, soft landings only.
          </p>
        </section>
      )}

      {running && (
        <>
          <section className="mt-5 flex items-center justify-center">
            <span
              className={`rounded-full border px-5 py-2 text-sm font-black tracking-wide ${PHASE_UI[phase].cls}`}
            >
              {PHASE_UI[phase].label}
              {phase === 'airborne' && flips > 0 && ` · ${flips} flip${flips > 1 ? 's' : ''}`}
            </span>
          </section>

          <section className="mt-4 grid grid-cols-4 gap-2 text-center">
            {[
              { label: 'Throws', value: String(stats.throws) },
              { label: 'Streak', value: stats.streak > 0 ? `${stats.streak}🔥` : '0' },
              { label: 'Best', value: String(stats.best) },
              { label: 'Big air', value: `${stats.biggestAir.toFixed(1)}s` },
            ].map((t) => (
              <div key={t.label} className="rounded-2xl border border-zinc-700 bg-zinc-900 px-1 py-2.5">
                <p className="text-lg font-black tabular-nums">{t.value}</p>
                <p className="text-[10px] uppercase tracking-wide text-zinc-500">{t.label}</p>
              </div>
            ))}
          </section>
        </>
      )}

      <button
        onClick={() => void simulate()}
        disabled={simulating}
        className="mt-4 w-full rounded-2xl border border-zinc-700 bg-zinc-900 px-4 py-3 text-sm font-semibold text-zinc-300 active:scale-95 disabled:opacity-50"
      >
        {simulating ? 'Simulating the sesh... 🖥️' : 'Simulate session (desktop demo) 🖥️'}
      </button>

      <section className="mt-6 space-y-3">
        {feed.length === 0 && running && (
          <p className="text-center text-sm text-zinc-500">
            No tricks yet. The sky is waiting, brah.
          </p>
        )}
        {feed.map((item) => (
          <TrickCard key={item.uid} result={item.result} line={item.line} />
        ))}
      </section>
    </main>
  );
}
