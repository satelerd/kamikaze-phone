import type { DetectedAttempt } from './types';

export function canonicalizeTrickName(trick: string): string {
  const normalized = trick.trim().toUpperCase();
  const legacyNames: Record<string, string> = {
    'FLIP +': 'PHONE FLIP',
    'FLIP −': 'REVERSE PHONE FLIP',
    'LONG ROLL +': 'PHONE FLIP',
    'LONG ROLL −': 'REVERSE PHONE FLIP',
    'PHONE FLIP +': 'FRONT FLIP',
    'PHONE FLIP −': 'BACK FLIP',
    'TRE COMBO': '360 FLIP',
  };
  return legacyNames[normalized] ?? trick;
}

export function migrateAttemptVocabulary(attempt: DetectedAttempt): DetectedAttempt {
  const trick = canonicalizeTrickName(attempt.trick);
  return trick === attempt.trick ? attempt : { ...attempt, trick };
}
