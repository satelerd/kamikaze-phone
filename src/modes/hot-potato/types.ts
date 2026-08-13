// Hot Potato mode: local types + tuning constants.
// Consumes shared engines from src/lib only; owns nothing outside this folder.

export type FusePresetId = 'short' | 'normal' | 'sudden';

export interface FusePreset {
  id: FusePresetId;
  label: string;
  emoji: string;
  blurb: string;
  /** fuse duration bounds in ms; actual fuse is random within, hidden from players */
  min: number;
  max: number;
}

export const FUSE_PRESETS: FusePreset[] = [
  {
    id: 'short',
    label: 'Short fuse',
    emoji: '⚡',
    blurb: 'Quick rounds, sweaty palms.',
    min: 8000,
    max: 15000,
  },
  {
    id: 'normal',
    label: 'Normal',
    emoji: '🔥',
    blurb: 'The classic backyard burn.',
    min: 12000,
    max: 25000,
  },
  {
    id: 'sudden',
    label: 'Sudden death',
    emoji: '💀',
    blurb: 'Barely time to blink.',
    min: 5000,
    max: 10000,
  },
];

export type PassOrder = 'circle' | 'chaos';

export interface HotPotatoConfig {
  /** player names in seating order */
  names: string[];
  fuse: FusePresetId;
  order: PassOrder;
}

export const MIN_PLAYERS = 2;
export const MAX_PLAYERS = 10;

/** tick interval at fuse start (ms) */
export const TICK_START_MS = 600;
/** tick interval at fuse end (ms) */
export const TICK_END_MS = 120;
