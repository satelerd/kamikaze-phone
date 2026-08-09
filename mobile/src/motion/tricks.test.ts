import { describe, expect, it } from 'vitest';

import { canonicalizeTrickName } from './tricks';

describe('trick vocabulary', () => {
  it('migrates the previous LONG ROLL label without changing its direction', () => {
    expect(canonicalizeTrickName('LONG ROLL +')).toBe('FLIP +');
    expect(canonicalizeTrickName('LONG ROLL −')).toBe('FLIP −');
  });
});
