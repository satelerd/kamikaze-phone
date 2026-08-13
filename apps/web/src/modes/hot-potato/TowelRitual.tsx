'use client';

// Pre-game towel ritual: full-screen safety recommendation with a looping
// pure-CSS animation of a phone getting wrapped in a towel. 3.6s loop:
// phone wiggles, towel flies in and orbits, burrito reveal, sparkles.
export default function TowelRitual({ onReady }: { onReady: () => void }) {
  return (
    <div className="fixed inset-0 z-40 flex flex-col items-center justify-center overflow-hidden bg-zinc-950 px-6 text-center">
      <div className="relative h-56 w-56">
        <div
          className="absolute left-1/2 top-1/2 h-44 w-44 rounded-full border-2 border-amber-400/25"
          style={{ animation: 'hp-ring 3.6s ease-in-out infinite' }}
        />
        <span
          className="absolute left-1/2 top-1/2 select-none text-7xl"
          style={{ animation: 'hp-towel-phone 3.6s ease-in-out infinite' }}
        >
          📱
        </span>
        <span
          className="absolute left-1/2 top-1/2 -ml-8 -mt-8 select-none text-6xl"
          style={{ animation: 'hp-towel-towel 3.6s ease-in-out infinite' }}
        >
          🧻
        </span>
        <span
          className="absolute left-1/2 top-1/2 select-none text-7xl"
          style={{ animation: 'hp-towel-wrap 3.6s ease-in-out infinite' }}
        >
          🌯
        </span>
        <span
          className="absolute left-6 top-8 select-none text-2xl"
          style={{ animation: 'hp-spark 3.6s ease-in-out infinite' }}
        >
          ✨
        </span>
        <span
          className="absolute right-5 top-16 select-none text-xl"
          style={{ animation: 'hp-spark 3.6s ease-in-out 0.15s infinite' }}
        >
          ✨
        </span>
        <span
          className="absolute bottom-8 left-1/2 select-none text-2xl"
          style={{ animation: 'hp-spark 3.6s ease-in-out 0.3s infinite' }}
        >
          ✨
        </span>
      </div>

      <h1 className="mt-6 text-3xl font-black">Wrap your phone in a towel.</h1>
      <p className="mt-1 text-xl font-bold text-amber-400">Trust the towel.</p>

      <div className="mt-6 w-full max-w-sm rounded-2xl border border-zinc-700 bg-zinc-900 p-4 text-left text-sm text-zinc-300">
        <p className="font-bold text-zinc-100">Real talk before liftoff:</p>
        <ul className="mt-2 space-y-1 text-zinc-400">
          <li>🧻 One snug wrap saves screens, corners, and friendships.</li>
          <li>🌱 Soft floor beats tile. Grass is king.</li>
          <li>🪭 Clear the ceiling fan zone. Seriously.</li>
          <li>🌯 Snug burrito, not mummy. It still needs to fly.</li>
        </ul>
      </div>

      <button
        onClick={onReady}
        className="mt-8 w-full max-w-sm rounded-2xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
      >
        IT&apos;S WRAPPED, LET&apos;S GO 🌯
      </button>

      <style>{`
        @keyframes hp-ring {
          0%, 100% { opacity: 0.25; transform: translate(-50%, -50%) scale(1); }
          50% { opacity: 0.7; transform: translate(-50%, -50%) scale(1.08); }
        }
        @keyframes hp-towel-phone {
          0% { opacity: 1; transform: translate(-50%, -50%) rotate(0deg) scale(1); }
          18% { opacity: 1; transform: translate(-50%, -50%) rotate(-10deg) scale(1); }
          30% { opacity: 1; transform: translate(-50%, -50%) rotate(8deg) scale(1); }
          40% { opacity: 1; transform: translate(-50%, -50%) rotate(0deg) scale(0.95); }
          52%, 100% { opacity: 0; transform: translate(-50%, -50%) scale(0.55); }
        }
        @keyframes hp-towel-towel {
          0%, 10% { opacity: 0; transform: translate(130px, -90px) rotate(0deg) scale(0.9); }
          22% { opacity: 1; transform: translate(48px, -34px) rotate(-30deg) scale(1); }
          32% { opacity: 1; transform: translate(-44px, 18px) rotate(-160deg) scale(1.05); }
          42% { opacity: 1; transform: translate(34px, 28px) rotate(-290deg) scale(1.05); }
          52% { opacity: 1; transform: translate(0, 0) rotate(-360deg) scale(1.25); }
          60%, 100% { opacity: 0; transform: translate(0, 0) rotate(-360deg) scale(0.4); }
        }
        @keyframes hp-towel-wrap {
          0%, 54% { opacity: 0; transform: translate(-50%, -50%) scale(0.3) rotate(0deg); }
          62% { opacity: 1; transform: translate(-50%, -50%) scale(1.3) rotate(0deg); }
          68% { opacity: 1; transform: translate(-50%, -50%) scale(0.92) rotate(-4deg); }
          74% { opacity: 1; transform: translate(-50%, -50%) scale(1.08) rotate(4deg); }
          80%, 94% { opacity: 1; transform: translate(-50%, -50%) scale(1) rotate(-6deg); }
          100% { opacity: 0; transform: translate(-50%, -50%) scale(1) rotate(0deg); }
        }
        @keyframes hp-spark {
          0%, 68% { opacity: 0; transform: scale(0.4); }
          78% { opacity: 1; transform: scale(1.2); }
          88% { opacity: 1; transform: scale(1); }
          100% { opacity: 0; transform: scale(0.6); }
        }
      `}</style>
    </div>
  );
}
