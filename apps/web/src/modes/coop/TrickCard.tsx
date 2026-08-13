'use client';

// Compact per-rider trick summary for the side-by-side result view.
import type { CoopGrade } from '@/lib/peer';
import type { RiderThrow } from './sync';

const GRADE_STYLES: Record<CoopGrade, string> = {
  S: 'bg-amber-400 text-zinc-950',
  A: 'bg-emerald-400 text-zinc-950',
  B: 'bg-sky-400 text-zinc-950',
  C: 'bg-zinc-500 text-zinc-950',
  BAIL: 'bg-red-500 text-zinc-950',
};

export default function TrickCard({ rider, label }: { rider: RiderThrow; label: string }) {
  return (
    <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
      <div className="text-[10px] uppercase tracking-widest text-zinc-400">{label}</div>
      <div className="mt-1 truncate text-lg font-black">{rider.trickName}</div>
      <div className="mt-2 flex items-center gap-2">
        <span className={`rounded-md px-2 py-0.5 text-xs font-black ${GRADE_STYLES[rider.grade]}`}>
          {rider.grade}
        </span>
        <span className="text-sm text-zinc-300">{rider.score} pts</span>
      </div>
      <div className="mt-2 text-xs text-zinc-400">Airtime {rider.airtime.toFixed(2)}s</div>
      <div className="truncate text-xs text-zinc-500">{rider.name}</div>
    </div>
  );
}
