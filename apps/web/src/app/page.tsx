'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { MODES } from '@/modes';
import { detectCapabilities } from '@/lib/capabilities';
import { getState, subscribe } from '@/lib/store';
import type { CapabilityReport } from '@/lib/types';
import ModeCard from '@/components/ModeCard';

export default function Home() {
  const router = useRouter();
  const [caps, setCaps] = useState<CapabilityReport | null>(null);
  const [stats, setStats] = useState({ best: 0, throws: 0, unlocked: 0 });

  useEffect(() => {
    const s = getState();
    if (!s.profile.setupDone) {
      router.replace('/setup');
      return;
    }
    setCaps(detectCapabilities());
    const sync = () => {
      const st = getState();
      setStats({ best: st.bestScore, throws: st.totalThrows, unlocked: Object.keys(st.achievements).length });
    };
    sync();
    return subscribe(sync);
  }, [router]);

  return (
    <main className="mx-auto min-h-screen max-w-3xl px-4 pb-24 pt-10">
      <header className="mb-8">
        <h1 className="text-4xl font-black tracking-tight">
          KAMIKAZE <span className="text-amber-400">PHONE</span>
        </h1>
        <p className="mt-1 text-zinc-400">Throw it. Flip it. Trust the towel. 🤙</p>
        <div className="mt-4 flex gap-4 text-sm text-zinc-300">
          <span>🏆 Best: <b>{stats.best}</b></span>
          <span>🌀 Throws: <b>{stats.throws}</b></span>
          <Link href="/achievements" className="underline decoration-amber-400/60 underline-offset-4">
            🎖️ Achievements: <b>{stats.unlocked}</b>
          </Link>
        </div>
      </header>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {MODES.map((m) => (
          <ModeCard key={m.id} mode={m} caps={caps} />
        ))}
      </div>

      <footer className="mt-10 flex items-center justify-between text-sm text-zinc-500">
        <Link href="/setup" className="underline underline-offset-4">Device setup</Link>
        <Link href="/test" className="underline underline-offset-4">Sensor lab</Link>
      </footer>
    </main>
  );
}
