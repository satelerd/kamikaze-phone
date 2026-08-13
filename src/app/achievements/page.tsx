'use client';

// Trophy shelf: every achievement, locked vs unlocked, with a progress header.
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { ACHIEVEMENTS } from '@/lib/achievements';
import { getState, subscribe } from '@/lib/store';

export default function AchievementsPage() {
  const [unlocked, setUnlocked] = useState<Record<string, { unlockedAt: number }>>({});

  useEffect(() => {
    setUnlocked(getState().achievements);
    return subscribe((s) => setUnlocked(s.achievements));
  }, []);

  const count = ACHIEVEMENTS.filter((a) => unlocked[a.id]).length;
  const pct = Math.round((count / ACHIEVEMENTS.length) * 100);

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-10">
      <Link href="/" className="text-sm text-zinc-400">
        ← Back to the lineup
      </Link>
      <h1 className="mt-2 text-3xl font-black">Trophy Shelf 🏆</h1>
      <p className="mt-1 text-sm text-zinc-400">
        {count} of {ACHIEVEMENTS.length} badges earned. Keep shredding, dude.
      </p>
      <div className="mt-3 h-2 overflow-hidden rounded-full bg-zinc-800">
        <div
          className="h-full bg-amber-400 transition-all duration-500"
          style={{ width: `${pct}%` }}
        />
      </div>

      <div className="mt-6 grid grid-cols-2 gap-3">
        {ACHIEVEMENTS.map((a) => {
          const u = unlocked[a.id];
          const hidden = !!a.secret && !u;
          return (
            <div
              key={a.id}
              className={`flex flex-col rounded-2xl border p-4 ${
                u
                  ? 'border-amber-400/50 bg-zinc-900'
                  : 'border-zinc-800 bg-zinc-900/40 opacity-60'
              }`}
            >
              <div className={`text-3xl ${u ? '' : 'grayscale'}`}>{hidden ? '❓' : a.emoji}</div>
              <div className="mt-2 text-sm font-bold leading-tight">
                {hidden ? '???' : a.name}
              </div>
              <div className="mt-1 flex-1 text-xs text-zinc-400">
                {hidden ? 'Secret. Keep riding to find out.' : a.description}
              </div>
              {u ? (
                <div className="mt-2 text-xs font-semibold text-amber-400">
                  🔓 {new Date(u.unlockedAt).toLocaleDateString()}
                </div>
              ) : (
                <div className="mt-2 text-xs text-zinc-600">🔒 Locked</div>
              )}
            </div>
          );
        })}
      </div>
    </main>
  );
}
