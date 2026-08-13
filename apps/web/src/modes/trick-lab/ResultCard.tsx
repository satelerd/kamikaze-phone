'use client';

// Trick result readout: name, grade, score, airtime, height, spins + style bars.
import type { TrickResult } from '@/lib/types';

const GRADE_EMOJI: Record<TrickResult['grade'], string> = {
  S: '🏆',
  A: '🔥',
  B: '👌',
  C: '🌱',
  BAIL: '🤕',
};

const GRADE_COLOR: Record<TrickResult['grade'], string> = {
  S: 'text-amber-300',
  A: 'text-amber-400',
  B: 'text-emerald-400',
  C: 'text-zinc-300',
  BAIL: 'text-red-400',
};

export default function ResultCard({ result }: { result: TrickResult }) {
  const f = result.features;
  const spins = Math.max(Math.abs(f.rotX), Math.abs(f.rotY), Math.abs(f.rotZ)) / 360;
  const stats: [string, string][] = [
    ['Airtime', `${f.airtime.toFixed(2)}s`],
    ['Height', `${f.height.toFixed(2)}m`],
    ['Spins', spins.toFixed(1)],
    ['Impact', `${f.impactG.toFixed(0)} m/s²`],
  ];
  const style: [string, number][] = [
    ['Amplitude', result.style.amplitude],
    ['Rotation', result.style.rotation],
    ['Cleanliness', result.style.cleanliness],
    ['Catch', result.style.catch],
    ['Commitment', result.style.commitment],
  ];

  return (
    <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h2 className="text-2xl font-black">{result.trickName}</h2>
          <p className="mt-1 text-sm text-zinc-400">{result.callout}</p>
        </div>
        <div className="text-right">
          <div className={`text-4xl font-black ${GRADE_COLOR[result.grade]}`}>
            {result.grade} {GRADE_EMOJI[result.grade]}
          </div>
          <div className="mt-1 text-sm text-zinc-400">
            score <b className="text-zinc-100">{result.score}</b>
          </div>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-4 gap-2 text-center">
        {stats.map(([label, value]) => (
          <div key={label} className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-2">
            <div className="text-xs text-zinc-500">{label}</div>
            <div className="mt-0.5 font-mono text-sm font-bold text-zinc-100">{value}</div>
          </div>
        ))}
      </div>

      <div className="mt-4 space-y-1.5">
        {style.map(([label, value]) => (
          <div key={label} className="flex items-center gap-2 text-xs">
            <span className="w-24 shrink-0 text-zinc-400">{label}</span>
            <div className="h-2 flex-1 overflow-hidden rounded-full bg-zinc-800">
              <div
                className="h-full rounded-full bg-amber-400"
                style={{ width: `${Math.max(2, Math.min(100, value))}%` }}
              />
            </div>
            <span className="w-8 text-right font-mono text-zinc-500">{Math.round(value)}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
