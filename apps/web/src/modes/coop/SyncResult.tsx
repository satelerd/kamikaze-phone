'use client';

// The big SYNC % moment: grade, breakdown bars, best-sync badge.
// Action buttons (rematch etc.) come in as children so every mode reuses it.
import type { ReactNode } from 'react';
import type { SyncBreakdown } from './sync';

const GRADE_META: Record<SyncBreakdown['grade'], { emoji: string; className: string }> = {
  'SOUL MATES': { emoji: '💞', className: 'text-amber-400' },
  'IN SYNC': { emoji: '🤝', className: 'text-emerald-400' },
  KINDA: { emoji: '🌊', className: 'text-sky-400' },
  CHAOS: { emoji: '🌪️', className: 'text-red-400' },
};

function Bar({ label, value, detail }: { label: string; value: number; detail?: string }) {
  return (
    <div>
      <div className="flex items-baseline justify-between text-xs">
        <span className="font-semibold text-zinc-300">{label}</span>
        <span className="text-zinc-400">
          {detail ? `${detail} · ` : ''}
          {Math.round(value)}%
        </span>
      </div>
      <div className="mt-1 h-2 overflow-hidden rounded-full bg-zinc-800">
        <div
          className="h-full rounded-full bg-amber-400"
          style={{ width: `${Math.max(2, Math.min(100, value))}%` }}
        />
      </div>
    </div>
  );
}

export default function SyncResult({
  bd,
  best,
  isNewBest,
  children,
}: {
  bd: SyncBreakdown;
  best: number;
  isNewBest: boolean;
  children?: ReactNode;
}) {
  const meta = GRADE_META[bd.grade];
  return (
    <section className="rounded-2xl border border-zinc-700 bg-zinc-900 p-5">
      <div className="text-center">
        <div className="text-xs uppercase tracking-[0.3em] text-zinc-400">Sync score</div>
        <div className="mt-1 text-7xl font-black tabular-nums text-amber-400">{bd.sync}%</div>
        <div className={`mt-1 text-2xl font-black ${meta.className}`}>
          {bd.grade} {meta.emoji}
        </div>
        {isNewBest ? (
          <div className="mt-2 inline-block rounded-full bg-amber-400 px-3 py-1 text-xs font-black text-zinc-950">
            NEW BEST 🏅
          </div>
        ) : (
          <div className="mt-2 text-xs text-zinc-500">Best sync: {best}%</div>
        )}
      </div>

      <div className="mt-5 space-y-3">
        {bd.simultaneity !== null && (
          <Bar
            label="Launch sync"
            value={bd.simultaneity}
            detail={`Δ ${Math.round(bd.launchDeltaMs ?? 0)}ms`}
          />
        )}
        <Bar
          label="Airtime match"
          value={bd.airtimeMatch}
          detail={`Δ ${Math.round(bd.airtimeDeltaPct * 100)}%`}
        />
        <Bar label="Combined style" value={bd.styleAvg} />
        <div className="flex items-center justify-between rounded-xl border border-zinc-800 bg-zinc-950/60 px-3 py-2 text-xs">
          <span className="font-semibold text-zinc-300">Trick match</span>
          <span className={bd.trickMatch ? 'font-black text-amber-400' : 'text-zinc-500'}>
            {bd.trickMatch ? 'SAME TRICK +15 🤙' : 'Different tricks, no bonus'}
          </span>
        </div>
      </div>

      {children ? <div className="mt-5 space-y-3">{children}</div> : null}
    </section>
  );
}
