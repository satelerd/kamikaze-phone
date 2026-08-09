export type GamePreferences = {
  onboardingComplete: boolean;
  selectedSkinId: string;
};

const KEY = 'kpf.game-preferences.v1';

export const DEFAULT_GAME_PREFERENCES: GamePreferences = {
  onboardingComplete: false,
  selectedSkinId: 'ion',
};

export async function loadGamePreferences(): Promise<GamePreferences> {
  try {
    const stored = globalThis.localStorage?.getItem(KEY);
    if (!stored) return DEFAULT_GAME_PREFERENCES;
    return { ...DEFAULT_GAME_PREFERENCES, ...JSON.parse(stored) };
  } catch {
    return DEFAULT_GAME_PREFERENCES;
  }
}

export async function saveGamePreferences(preferences: GamePreferences): Promise<void> {
  globalThis.localStorage?.setItem(KEY, JSON.stringify(preferences));
}
