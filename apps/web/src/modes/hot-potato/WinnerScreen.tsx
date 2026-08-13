'use client';

// Winner screen: fanfare, CSS confetti, hall of champions from localStorage.
import { useEffect, useMemo, useRef, useState } from 'react';
import { AudioBus } from '@/lib/audio';
import { speak } from '@/lib/speech';
import { winnerLine } from './lines';
import { getWins } from './wins';

const CONFETTI_COLORS = ['#fbbf24', '#f87171', '#34d399', '#60a5fa', '#e879f9', '#fb923c'];

interface WinnerScreenProps {
  winner: string;
  onRunBack: () => void;
  onNewCrew: () => void;
}

export default function WinnerScreen({ winner, onRunBack, onNewCrew }: WinnerScreenProps) {
  const [wins, setWins] = useState<Record<string, number>>({});
  const celebrated = useRef(false);

  useEffect(() => {
    setWins(getWins());
    if (celebrated.current) return;
    celebrated.current = true;
    void AudioBus.play('fanfare');
    speak(winnerLine(winner), { style: 'caller', forceLocal: true, interrupt: true });
  }, [winner]);

  const confetti = useMemo(
    () =>
      Array.from({ length: 60 }, (_, i) => ({
        left: Math.random() * 100,
        delay: Math.random() * 2.5,
        dur: 2.8 + Math.random() * 2.2,
        size: 6 + Math.random() * 7,
        color: CONFETTI_COLORS[i % CONFETTI_COLORS.length],
      })),
    [],
  );

  const board = Object.entries(wins)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8);

  return (
    <div className="relative">
      {confetti.map((c, i) => (
        <span
          key={i}
          aria-hidden
          className="pointer-events-none fixed z-30 block rounded-sm"
          style={{
            top: '-24px',
            left: `${c.left}%`,
            width: c.size,
            height: c.size * 0.45,
            backgroundColor: c.color,
            animation: `hp-confetti ${c.dur.toFixed(2)}s linear ${c.delay.toFixed(2)}s infinite`,
          }}
        />
      ))}

      <div className="flex flex-col items-center pt-10 text-center">
        <span className="text-8xl">🏆</span>
        <p className="mt-4 text-sm uppercase tracking-widest text-zinc-500">
          Last rider standing
        </p>
        <h1 className="mt-1 break-words text-5xl font-black text-amber-400">{winner}</h1>
        <p className="mt-3 text-zinc-400">Survived the spud. Absolute legend.</p>
      </div>

      {board.length > 0 && (
        <section className="mt-8 rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
          <p className="text-sm font-bold text-zinc-300">Hall of Champions 🥔</p>
          <ul className="mt-2 space-y-1 text-sm">
            {board.map(([name, count], i) => (
              <li key={name} className="flex items-center justify-between">
                <span className={name === winner ? 'font-bold text-amber-300' : 'text-zinc-300'}>
                  {i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : '🏅'} {name}
                </span>
                <span className="text-zinc-400">
                  {count} {count === 1 ? 'win' : 'wins'}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <button
        onClick={onRunBack}
        className="mt-8 w-full rounded-2xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
      >
        RUN IT BACK 🔁
      </button>
      <button
        onClick={onNewCrew}
        className="mt-3 w-full rounded-2xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold text-zinc-300 active:scale-95"
      >
        New crew 👥
      </button>

      <style>{`
        @keyframes hp-confetti {
          0% { transform: translateY(0) rotate(0deg); opacity: 1; }
          100% { transform: translateY(115vh) rotate(720deg); opacity: 0.6; }
        }
      `}</style>
    </div>
  );
}
