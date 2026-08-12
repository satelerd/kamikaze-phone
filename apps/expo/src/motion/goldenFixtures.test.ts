import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import { buildReplayFrames, normalizeReplayFrames } from './replay';
import type { DetectedAttempt } from './types';

type LabelledCapture = {
  expectedTrick: string;
  recordedAttempt: DetectedAttempt;
  schema: 'kpf-labelled-capture-v1';
};

const fixtureDirectory = decodeURIComponent(
  new URL('../../../../fixtures/motion/v2/labelled/', import.meta.url).pathname,
);

const cases = [
  ['iphone15plus-right-phone-flip-001.json', 'PHONE FLIP', 202],
  ['iphone15plus-right-reverse-phone-flip-001.json', 'REVERSE PHONE FLIP', 217],
] as const;

describe('real iPhone golden fixtures', () => {
  it.each(cases)('preserves and reconstructs %s', (file, expectedTrick, sampleCount) => {
    const capture = JSON.parse(readFileSync(`${fixtureDirectory}${file}`, 'utf8')) as LabelledCapture;
    const frames = normalizeReplayFrames(buildReplayFrames(capture.recordedAttempt));

    expect(capture.schema).toBe('kpf-labelled-capture-v1');
    expect(capture.expectedTrick).toBe(expectedTrick);
    expect(capture.recordedAttempt.schemaVersion).toBe(2);
    expect(capture.recordedAttempt.source).toBe('sensor');
    expect(capture.recordedAttempt.sampleCount).toBe(sampleCount);
    expect(capture.recordedAttempt.samples).toHaveLength(sampleCount);
    expect(frames).toHaveLength(sampleCount);
    expect(frames[0].timestampMs).toBe(0);
    expect(frames.at(-1)?.progress).toBe(1);
    expect(frames.every((frame, index) => index === 0 || frame.timestampMs >= frames[index - 1].timestampMs)).toBe(true);
  });
});
