import Storage from 'expo-sqlite/kv-store';

export type GamePreferences = {
  onboardingComplete: boolean;
  selectedSkinId: string;
  showPerformanceHud: boolean;
};

const KEY = 'kpf.game-preferences.v1';

export const DEFAULT_GAME_PREFERENCES: GamePreferences = {
  onboardingComplete: false,
  selectedSkinId: 'ion',
  showPerformanceHud: false,
};

export async function loadGamePreferences(): Promise<GamePreferences> {
  try {
    const stored = await Storage.getItem(KEY);
    if (!stored) return DEFAULT_GAME_PREFERENCES;
    return { ...DEFAULT_GAME_PREFERENCES, ...JSON.parse(stored) };
  } catch {
    return DEFAULT_GAME_PREFERENCES;
  }
}

export async function saveGamePreferences(preferences: GamePreferences): Promise<void> {
  await Storage.setItem(KEY, JSON.stringify(preferences));
}
