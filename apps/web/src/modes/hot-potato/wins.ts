// Hot Potato win ledger: persisted under this mode's own localStorage key
// (separate from the shared kamikaze store, which this mode never reshapes).

const KEY = 'kamikaze-hot-potato-wins-v1';

export function getWins(): Record<string, number> {
  if (typeof window === 'undefined') return {};
  try {
    const raw = window.localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Record<string, number>) : {};
  } catch {
    return {};
  }
}

/** Increment a player's win count and return the updated ledger. */
export function bumpWin(name: string): Record<string, number> {
  const wins = getWins();
  wins[name] = (wins[name] ?? 0) + 1;
  if (typeof window !== 'undefined') {
    try {
      window.localStorage.setItem(KEY, JSON.stringify(wins));
    } catch {
      // storage full or private mode: the round still counts in memory
    }
  }
  return wins;
}
