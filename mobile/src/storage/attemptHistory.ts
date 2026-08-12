import Storage from 'expo-sqlite/kv-store';

import type { DetectedAttempt } from '../motion/types';
import { migrateAttemptVocabulary } from '../motion/tricks';

const HISTORY_KEY = 'kpf.attempt-history.v2';
const MAX_ATTEMPTS = 50;

function isStoredAttempt(value: unknown): value is DetectedAttempt {
  if (!value || typeof value !== 'object') return false;
  const attempt = value as Partial<DetectedAttempt>;
  return attempt.schemaVersion === 2 &&
    typeof attempt.id === 'string' &&
    typeof attempt.trick === 'string' &&
    Array.isArray(attempt.samples);
}

export async function loadAttemptHistory(): Promise<DetectedAttempt[]> {
  try {
    const stored = await Storage.getItem(HISTORY_KEY);
    if (!stored) return [];
    const parsed: unknown = JSON.parse(stored);
    return Array.isArray(parsed)
      ? parsed.filter(isStoredAttempt).map(migrateAttemptVocabulary).slice(0, MAX_ATTEMPTS)
      : [];
  } catch {
    return [];
  }
}

export async function saveAttemptHistory(attempts: DetectedAttempt[]): Promise<void> {
  await Storage.setItem(
    HISTORY_KEY,
    JSON.stringify(attempts.map(migrateAttemptVocabulary).slice(0, MAX_ATTEMPTS)),
  );
}
