'use client';

// Co-op Sync: two phones, one trick. Pair over PeerJS (QR invite + room code),
// throw on a shared countdown, score the coordination. Single-phone pass mode
// and a desktop simulation cover every hardware situation.
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { useEffect, useState } from 'react';
import { FXEngine } from '@/lib/fx';
import { normalizeRoomCode } from '@/lib/peer';
import { getState } from '@/lib/store';
import LinkedMode from './LinkedMode';
import PassMode from './PassMode';
import SimMode from './SimMode';
import { loadBestSync } from './sync';

type Screen = 'menu' | 'linked' | 'pass' | 'sim';

function MenuCard({
  emoji,
  title,
  blurb,
  onClick,
  primary = false,
}: {
  emoji: string;
  title: string;
  blurb: string;
  onClick: () => void;
  primary?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={`w-full rounded-2xl border p-4 text-left active:scale-95 ${
        primary ? 'border-amber-400/70 bg-amber-400/10' : 'border-zinc-700 bg-zinc-900'
      }`}
    >
      <div className="flex items-center gap-3">
        <span className="text-3xl">{emoji}</span>
        <div className="min-w-0">
          <div className="text-lg font-black">{title}</div>
          <div className="mt-0.5 text-xs text-zinc-400">{blurb}</div>
        </div>
      </div>
    </button>
  );
}

export default function CoopGame() {
  const params = useSearchParams();
  const joinCode = normalizeRoomCode(params.get('join') ?? '');
  const [screen, setScreen] = useState<Screen>(joinCode ? 'linked' : 'menu');
  const [name, setName] = useState('Rider');
  const [best, setBest] = useState(0);

  useEffect(() => {
    setName(getState().profile.playerName || 'Rider');
    setBest(loadBestSync());
  }, [screen]);

  const go = (s: Screen) => {
    FXEngine.handle({ type: 'ui-select' });
    setScreen(s);
  };

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-8">
      <header className="mb-4">
        <h1 className="text-3xl font-black tracking-tight">
          CO-OP <span className="text-amber-400">SYNC</span> 🤝
        </h1>
        <p className="mt-1 text-sm text-zinc-400">
          Two phones, one trick. Coordination is the score.
        </p>
      </header>

      <nav className="mb-6 flex items-center justify-between text-sm">
        {screen === 'menu' ? (
          <Link href="/" className="text-zinc-400 underline underline-offset-4">
            ← Home
          </Link>
        ) : (
          <button onClick={() => go('menu')} className="text-zinc-400 underline underline-offset-4">
            ← Co-op menu
          </button>
        )}
        <span className="text-zinc-500">
          🏅 Best sync: <b className="text-zinc-300">{best}%</b>
        </span>
      </nav>

      {screen === 'menu' && (
        <div className="space-y-4">
          <MenuCard
            emoji="📱📱"
            title="Two Phones"
            blurb="Pair over the airwaves. QR handshake, synced countdown, zero backend."
            onClick={() => go('linked')}
            primary
          />
          <MenuCard
            emoji="🔁"
            title="Pass Mode"
            blurb="One phone, two riders. A sets the line, B matches the airtime and the trick."
            onClick={() => go('pass')}
          />
          <MenuCard
            emoji="🖥️"
            title="Simulate Both Riders"
            blurb="Desktop demo. Two synthetic throws through the full scoring path."
            onClick={() => go('sim')}
          />
        </div>
      )}

      {screen === 'linked' && <LinkedMode playerName={name} initialJoinCode={joinCode || undefined} />}
      {screen === 'pass' && <PassMode playerName={name} />}
      {screen === 'sim' && <SimMode />}
    </main>
  );
}
