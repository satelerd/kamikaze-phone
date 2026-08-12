import type { GripHand, TrickDefinition } from '../motion/trickCatalog';

const DEFINITIONS_KEY = 'kpf.custom-trick-catalog.v1';
const GRIP_KEY = 'kpf.grip-hand.v1';

export async function loadCustomTricks(): Promise<TrickDefinition[]> {
  try {
    const stored = globalThis.localStorage?.getItem(DEFINITIONS_KEY);
    if (!stored) return [];
    const parsed: unknown = JSON.parse(stored);
    return Array.isArray(parsed) ? parsed as TrickDefinition[] : [];
  } catch {
    return [];
  }
}

export async function saveCustomTricks(definitions: TrickDefinition[]): Promise<void> {
  globalThis.localStorage?.setItem(
    DEFINITIONS_KEY,
    JSON.stringify(definitions.filter(({ builtIn }) => !builtIn)),
  );
}

export async function loadGripHand(): Promise<GripHand> {
  return globalThis.localStorage?.getItem(GRIP_KEY) === 'left' ? 'left' : 'right';
}

export async function saveGripHand(hand: GripHand): Promise<void> {
  globalThis.localStorage?.setItem(GRIP_KEY, hand);
}
