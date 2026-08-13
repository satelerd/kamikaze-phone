'use client';

// Synchronized 3-2-1 driven by a wall-clock startAt (already corrected into
// the local clock by the caller), so two phones tick the same beat.
import { useEffect, useRef, useState } from 'react';
import { FXEngine } from '@/lib/fx';

export default function Countdown({
  startAt,
  onGo,
  subtitle,
  hint,
}: {
  /** local epoch ms when the throw window opens */
  startAt: number;
  onGo: () => void;
  subtitle?: string;
  hint?: string;
}) {
  const [n, setN] = useState(() => Math.max(0, Math.ceil((startAt - Date.now()) / 1000)));
  const goneRef = useRef(false);
  const onGoRef = useRef(onGo);
  onGoRef.current = onGo;

  useEffect(() => {
    goneRef.current = false;
    let last = -1;
    let raf = 0;
    const loop = () => {
      const remain = startAt - Date.now();
      const cur = Math.max(0, Math.ceil(remain / 1000));
      if (cur !== last) {
        last = cur;
        setN(cur);
        if (cur > 0) FXEngine.handle({ type: 'countdown-tick', n: cur });
      }
      if (remain <= 0) {
        if (!goneRef.current) {
          goneRef.current = true;
          onGoRef.current();
        }
        return;
      }
      raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    return () => cancelAnimationFrame(raf);
  }, [startAt]);

  return (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-zinc-700 bg-zinc-900 py-14 text-center">
      <div className="text-xs uppercase tracking-[0.3em] text-zinc-400">
        {subtitle ?? 'Throw on zero'}
      </div>
      <div className="mt-4 text-9xl font-black tabular-nums text-amber-400">
        {n > 3 ? '🤙' : n > 0 ? n : '🚀'}
      </div>
      <div className="mt-4 text-sm text-zinc-400">{hint ?? 'Same beat. SEND IT on zero.'}</div>
    </div>
  );
}
