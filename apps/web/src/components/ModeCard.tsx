'use client';

import Link from 'next/link';
import type { CapabilityReport, ModeDefinition } from '@/lib/types';
import { capabilityOk, CAPABILITY_LABELS } from '@/lib/capabilities';
import { FXEngine } from '@/lib/fx';

export default function ModeCard({ mode, caps }: { mode: ModeDefinition; caps: CapabilityReport | null }) {
  const missing = caps ? mode.requires.filter((k) => !capabilityOk(caps[k])) : [];
  const locked = missing.length > 0;

  const inner = (
    <div
      className={`relative flex h-full flex-col justify-between rounded-2xl border p-4 transition-transform active:scale-95 ${
        locked
          ? 'border-zinc-800 bg-zinc-900/40 opacity-60'
          : 'border-zinc-700 bg-zinc-900 hover:border-amber-400/60'
      }`}
    >
      <div>
        <div className="text-3xl">{mode.emoji}</div>
        <h3 className="mt-2 text-lg font-bold">{mode.title}</h3>
        <p className="mt-1 text-sm text-zinc-400">{mode.tagline}</p>
      </div>
      {locked && (
        <p className="mt-3 text-xs text-amber-400/80">
          🔒 {mode.lockedHint ?? `Needs: ${missing.map((k) => CAPABILITY_LABELS[k]).join(', ')}`}
        </p>
      )}
    </div>
  );

  if (locked) return <div className="h-full">{inner}</div>;
  return (
    <Link href={mode.path} className="h-full" onClick={() => FXEngine.handle({ type: 'ui-select' })}>
      {inner}
    </Link>
  );
}
