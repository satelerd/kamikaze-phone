'use client';

// Placeholder narrator dock: replaced by the full ElevenLabs surfer narrator.
// Keeps the mute toggle working from day one.
import { useEffect, useState } from 'react';
import { getState, subscribe, updateSettings } from '@/lib/store';

export default function NarratorDock() {
  const [muted, setMuted] = useState(false);

  useEffect(() => {
    setMuted(getState().settings.muted);
    return subscribe((s) => setMuted(s.settings.muted));
  }, []);

  return (
    <button
      onClick={() => updateSettings({ muted: !muted })}
      className="fixed bottom-4 right-4 z-50 flex h-12 w-12 items-center justify-center rounded-full bg-zinc-800/90 text-xl shadow-lg backdrop-blur"
      aria-label={muted ? 'Unmute' : 'Mute'}
    >
      {muted ? '🔇' : '🔊'}
    </button>
  );
}
