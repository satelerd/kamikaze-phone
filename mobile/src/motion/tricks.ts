import type { DetectedAttempt } from './types';

export function canonicalizeTrickName(trick: string): string {
  return trick.replace(/LONG ROLL/gi, 'FLIP');
}

export function migrateAttemptVocabulary(attempt: DetectedAttempt): DetectedAttempt {
  const trick = canonicalizeTrickName(attempt.trick);
  return trick === attempt.trick ? attempt : { ...attempt, trick };
}
