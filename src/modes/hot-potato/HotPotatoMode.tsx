'use client';

// Hot Potato mode root: setup -> towel ritual -> game rounds -> winner.
// Sensors start once at the towel acknowledge (user gesture, unlocks audio +
// iOS motion permission) and keep running for the whole game.
import { useState } from 'react';
import Link from 'next/link';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import { SensorEngine } from '@/lib/sensors';
import { unlockAchievement } from '@/lib/store';
import GameScreen from './GameScreen';
import SetupScreen from './SetupScreen';
import TowelRitual from './TowelRitual';
import WinnerScreen from './WinnerScreen';
import type { HotPotatoConfig } from './types';
import { bumpWin } from './wins';

type Stage = 'setup' | 'towel' | 'playing' | 'winner';

export default function HotPotatoMode() {
  const [stage, setStage] = useState<Stage>('setup');
  const [config, setConfig] = useState<HotPotatoConfig | null>(null);
  const [winner, setWinner] = useState<string | null>(null);
  const [gameKey, setGameKey] = useState(0);

  const handleStart = (cfg: HotPotatoConfig) => {
    FXEngine.handle({ type: 'ui-start' });
    setConfig(cfg);
    setStage('towel');
  };

  const handleTowelAck = async () => {
    try {
      if (unlockAchievement('towel-believer')) {
        FXEngine.handle({ type: 'achievement', id: 'towel-believer' });
      }
    } catch {
      // achievements registry not wired yet: the towel still protects
    }
    AudioBus.ensure();
    await SensorEngine.get().requestPermission();
    SensorEngine.get().start();
    FXEngine.handle({ type: 'ui-start' });
    setGameKey((k) => k + 1);
    setStage('playing');
  };

  const handleWinner = (name: string) => {
    bumpWin(name);
    setWinner(name);
    setStage('winner');
  };

  const runItBack = () => {
    // Same crew, same rules: they already trust the towel, skip the ritual.
    setGameKey((k) => k + 1);
    setStage('playing');
  };

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-16 pt-6">
      <div className="mb-4 flex items-center justify-between">
        <Link href="/" className="text-sm text-zinc-400">
          ← Back
        </Link>
        <span className="text-sm font-bold text-amber-400">🥔 Hot Potato</span>
      </div>

      {stage === 'setup' && <SetupScreen onStart={handleStart} />}
      {stage === 'towel' && <TowelRitual onReady={() => void handleTowelAck()} />}
      {stage === 'playing' && config && (
        <GameScreen
          key={gameKey}
          config={config}
          onWinner={handleWinner}
          onQuit={() => setStage('setup')}
        />
      )}
      {stage === 'winner' && winner && (
        <WinnerScreen
          winner={winner}
          onRunBack={runItBack}
          onNewCrew={() => setStage('setup')}
        />
      )}
    </main>
  );
}
