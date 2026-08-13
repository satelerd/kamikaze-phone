// On-device state: profile, settings, trick history, achievements.
// localStorage + tiny pub/sub; no backend.
import type { DevicePresetId, TrickResult } from './types';

export interface Profile {
  playerName: string;
  device: DevicePresetId | null;
  setupDone: boolean;
}

export interface Settings {
  muted: boolean;
  narratorEnabled: boolean;
  hapticsEnabled: boolean;
  torchEnabled: boolean;
  musicVolume: number;
  sfxVolume: number;
}

export interface PersistedState {
  v: 1;
  profile: Profile;
  settings: Settings;
  history: TrickResult[];
  achievements: Record<string, { unlockedAt: number }>;
  bestScore: number;
  totalThrows: number;
}

const KEY = 'kamikaze-state-v1';
const MAX_HISTORY = 200;

const DEFAULTS: PersistedState = {
  v: 1,
  profile: { playerName: '', device: null, setupDone: false },
  settings: {
    muted: false, narratorEnabled: true, hapticsEnabled: true, torchEnabled: true,
    musicVolume: 0.6, sfxVolume: 1.0,
  },
  history: [],
  achievements: {},
  bestScore: 0,
  totalThrows: 0,
};

type Listener = (s: PersistedState) => void;
const listeners = new Set<Listener>();
let cache: PersistedState | null = null;

export function getState(): PersistedState {
  if (cache) return cache;
  if (typeof window === 'undefined') return structuredClone(DEFAULTS);
  try {
    const raw = window.localStorage.getItem(KEY);
    cache = raw ? { ...structuredClone(DEFAULTS), ...JSON.parse(raw) } : structuredClone(DEFAULTS);
  } catch {
    cache = structuredClone(DEFAULTS);
  }
  return cache!;
}

export function setState(patch: Partial<PersistedState>): PersistedState {
  const next = { ...getState(), ...patch };
  cache = next;
  if (typeof window !== 'undefined') {
    try {
      window.localStorage.setItem(KEY, JSON.stringify(next));
    } catch {
      // storage full or private mode: keep going in-memory
    }
  }
  listeners.forEach((cb) => cb(next));
  return next;
}

export function subscribe(cb: Listener): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function recordTrick(result: TrickResult): PersistedState {
  const s = getState();
  const history = [result, ...s.history].slice(0, MAX_HISTORY);
  return setState({
    history,
    totalThrows: s.totalThrows + 1,
    bestScore: Math.max(s.bestScore, result.score),
  });
}

/** Returns true if this call newly unlocked the achievement. */
export function unlockAchievement(id: string): boolean {
  const s = getState();
  if (s.achievements[id]) return false;
  setState({ achievements: { ...s.achievements, [id]: { unlockedAt: Date.now() } } });
  return true;
}

export function updateSettings(patch: Partial<Settings>): PersistedState {
  return setState({ settings: { ...getState().settings, ...patch } });
}

export function updateProfile(patch: Partial<Profile>): PersistedState {
  return setState({ profile: { ...getState().profile, ...patch } });
}
