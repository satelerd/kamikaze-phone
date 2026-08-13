'use client';

// Rich result card for one trick: grade badge, the 5 style dimensions as bars,
// flight stats, a mini side-view trajectory sparkline, and Bodhi's line.
// `compact` renders a one-row summary for dense lists.
import { useEffect, useRef } from 'react';
import type { TrickResult } from '@/lib/types';

const GRADE_STYLES: Record<TrickResult['grade'], string> = {
  S: 'bg-amber-300 text-zinc-950 shadow-[0_0_18px_rgba(251,191,36,0.65)]',
  A: 'bg-emerald-400 text-zinc-950',
  B: 'bg-sky-400 text-zinc-950',
  C: 'bg-zinc-600 text-zinc-100',
  BAIL: 'bg-red-500 text-zinc-50 shadow-[0_0_18px_rgba(239,68,68,0.55)]',
};

const DIMS: { key: keyof TrickResult['style']; label: string }[] = [
  { key: 'amplitude', label: 'Amplitude' },
  { key: 'rotation', label: 'Rotation' },
  { key: 'cleanliness', label: 'Cleanliness' },
  { key: 'catch', label: 'Catch' },
  { key: 'commitment', label: 'Commitment' },
];

function spinsFor(result: TrickResult, axis: 'rotX' | 'rotY' | 'rotZ'): string {
  return (Math.abs(result.features[axis]) / 360).toFixed(1);
}

function TrajectorySparkline({ result }: { result: TrickResult }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const points = result.trajectory;
    const dpr = typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1;
    const w = canvas.clientWidth || 120;
    const h = canvas.clientHeight || 48;
    canvas.width = w * dpr;
    canvas.height = h * dpr;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, w, h);

    // ground line
    const pad = 4;
    ctx.strokeStyle = 'rgba(113,113,122,0.6)'; // zinc-500
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(pad, h - pad);
    ctx.lineTo(w - pad, h - pad);
    ctx.stroke();

    if (points.length < 2) return;
    const tMax = points[points.length - 1].t || 1;
    const yMax = Math.max(0.2, ...points.map((p) => p.y));

    ctx.strokeStyle = result.grade === 'BAIL' ? 'rgba(239,68,68,0.95)' : 'rgba(251,191,36,0.95)';
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.beginPath();
    points.forEach((p, i) => {
      const x = pad + (p.t / tMax) * (w - pad * 2);
      const y = h - pad - (Math.max(0, p.y) / yMax) * (h - pad * 2);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    });
    ctx.stroke();

    // apex marker
    let apex = points[0];
    for (const p of points) if (p.y > apex.y) apex = p;
    const ax = pad + (apex.t / tMax) * (w - pad * 2);
    const ay = h - pad - (Math.max(0, apex.y) / yMax) * (h - pad * 2);
    ctx.fillStyle = 'rgba(251,191,36,1)';
    ctx.beginPath();
    ctx.arc(ax, ay, 2.5, 0, Math.PI * 2);
    ctx.fill();
  }, [result]);

  return (
    <canvas
      ref={canvasRef}
      className="h-12 w-full rounded-lg bg-zinc-950/60"
      role="img"
      aria-label="Trajectory side view"
    />
  );
}

export interface TrickCardProps {
  result: TrickResult;
  /** what the narrator said about this exact throw */
  line?: string | null;
  compact?: boolean;
}

export default function TrickCard({ result, line, compact = false }: TrickCardProps) {
  if (compact) {
    return (
      <div className="flex items-center gap-3 rounded-2xl border border-zinc-700 bg-zinc-900 px-3 py-2">
        <span
          className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-sm font-black ${GRADE_STYLES[result.grade]}`}
        >
          {result.grade === 'BAIL' ? '✗' : result.grade}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-bold">{result.trickName}</p>
          <p className="text-xs text-zinc-400">
            {result.features.airtime.toFixed(2)}s air · {result.score} pts
          </p>
        </div>
      </div>
    );
  }

  return (
    <article className="rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
      <header className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-lg font-black leading-tight">{result.trickName}</h3>
          <p className="text-xs text-zinc-500">
            {new Date(result.at).toLocaleTimeString()} · {result.mode}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-2xl font-black tabular-nums text-zinc-100">{result.score}</span>
          <span
            className={`flex h-10 w-10 items-center justify-center rounded-xl text-lg font-black ${GRADE_STYLES[result.grade]}`}
          >
            {result.grade === 'BAIL' ? '💥' : result.grade}
          </span>
        </div>
      </header>

      <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div className="space-y-1.5">
          {DIMS.map(({ key, label }) => (
            <div key={key} className="flex items-center gap-2">
              <span className="w-24 shrink-0 text-[11px] uppercase tracking-wide text-zinc-400">
                {label}
              </span>
              <div className="h-2 flex-1 overflow-hidden rounded-full bg-zinc-800">
                <div
                  className={`h-full rounded-full ${result.grade === 'BAIL' ? 'bg-red-500/80' : 'bg-amber-400'}`}
                  style={{ width: `${Math.round(result.style[key])}%` }}
                />
              </div>
              <span className="w-7 text-right text-[11px] tabular-nums text-zinc-500">
                {Math.round(result.style[key])}
              </span>
            </div>
          ))}
        </div>

        <div className="flex flex-col gap-2">
          <TrajectorySparkline result={result} />
          <div className="grid grid-cols-3 gap-1 text-center text-xs">
            <div className="rounded-lg bg-zinc-800/70 px-1 py-1.5">
              <p className="font-bold tabular-nums">{result.features.airtime.toFixed(2)}s</p>
              <p className="text-[10px] text-zinc-500">airtime</p>
            </div>
            <div className="rounded-lg bg-zinc-800/70 px-1 py-1.5">
              <p className="font-bold tabular-nums">{result.features.height.toFixed(2)}m</p>
              <p className="text-[10px] text-zinc-500">height</p>
            </div>
            <div className="rounded-lg bg-zinc-800/70 px-1 py-1.5">
              <p className="font-bold tabular-nums">
                {spinsFor(result, 'rotX')}/{spinsFor(result, 'rotY')}/{spinsFor(result, 'rotZ')}
              </p>
              <p className="text-[10px] text-zinc-500">spins x/y/z</p>
            </div>
          </div>
        </div>
      </div>

      {line && (
        <p className="mt-3 rounded-xl border border-amber-400/20 bg-amber-400/5 px-3 py-2 text-sm italic text-amber-200/90">
          🏄 {line}
        </p>
      )}
    </article>
  );
}
