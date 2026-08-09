import Storage from 'expo-sqlite/kv-store';

import type { GripHand, TrickDefinition } from '../motion/trickCatalog';

const DEFINITIONS_KEY = 'kpf.custom-trick-catalog.v1';
const GRIP_KEY = 'kpf.grip-hand.v1';

export async function loadCustomTricks(): Promise<TrickDefinition[]> {
  try {
    const stored = await Storage.getItem(DEFINITIONS_KEY);
    if (!stored) return [];
    const parsed: unknown = JSON.parse(stored);
    return Array.isArray(parsed) ? parsed as TrickDefinition[] : [];
  } catch {
    return [];
  }
}

export async function saveCustomTricks(definitions: TrickDefinition[]): Promise<void> {
  await Storage.setItem(DEFINITIONS_KEY, JSON.stringify(definitions.filter(({ builtIn }) => !builtIn)));
}

export async function loadGripHand(): Promise<GripHand> {
  const stored = await Storage.getItem(GRIP_KEY);
  return stored === 'left' ? 'left' : 'right';
}

export async function saveGripHand(hand: GripHand): Promise<void> {
  await Storage.setItem(GRIP_KEY, hand);
}
