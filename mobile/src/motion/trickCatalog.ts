import type { DetectedAttempt, RotationSummary, Vector3 } from './types';

export type GripHand = 'right' | 'left';

export type TrickFamily = 'air' | 'flip' | 'shuvit' | 'combo' | 'custom';

export type TrickDefinition = {
  aliases: string[];
  builtIn: boolean;
  description: string;
  durationMs: number;
  exampleCount: number;
  family: TrickFamily;
  id: string;
  name: string;
  rotation: Vector3;
  source: 'system' | 'recording';
};

export type TrickMatch = {
  axisPurity: number;
  definition: TrickDefinition;
  landingScore: number;
  motionDurationMs: number;
  overallScore: number;
  rotationScore: number;
  timingScore: number;
};

const clamp = (value: number, minimum = 0, maximum = 1) =>
  Math.min(maximum, Math.max(minimum, value));

const magnitude = (value: Vector3) => Math.hypot(value.x, value.y, value.z);

const signed = (value: number, hand: GripHand) => value * (hand === 'right' ? 1 : -1);

export function buildDefaultTrickCatalog(hand: GripHand): TrickDefinition[] {
  const y = (value: number) => signed(value, hand);
  const z = (value: number) => signed(value, hand);
  return [
    {
      aliases: ['STRAIGHT AIR', 'AIR'], builtIn: true,
      description: 'No flip and no spin. Release it flat and catch it flat.',
      durationMs: 520, exampleCount: 0, family: 'air', id: 'straight-air', name: 'STRAIGHT AIR',
      rotation: { x: 0, y: 0, z: 0 }, source: 'system',
    },
    {
      aliases: ['360 FLIP', 'TRE COMBO', 'FLIP 3'], builtIn: true,
      description: 'One edge flip plus one full flat spin. Skate analogue: 360 Flip.',
      durationMs: 820, exampleCount: 0, family: 'combo', id: 'phone-flip', name: 'PHONE FLIP',
      rotation: { x: 0, y: y(360), z: z(360) }, source: 'system',
    },
    {
      aliases: ['LASER FLIP'], builtIn: true,
      description: 'The reverse edge flip plus reverse full spin. Skate analogue: Laser Flip.',
      durationMs: 820, exampleCount: 0, family: 'combo', id: 'reverse-phone-flip', name: 'REVERSE PHONE FLIP',
      rotation: { x: 0, y: y(-360), z: z(-360) }, source: 'system',
    },
    {
      aliases: ['PHONE FLIP +'], builtIn: true,
      description: 'One forward rotation around the phone width.',
      durationMs: 620, exampleCount: 0, family: 'flip', id: 'front-flip', name: 'FRONT FLIP',
      rotation: { x: 360, y: 0, z: 0 }, source: 'system',
    },
    {
      aliases: ['PHONE FLIP −'], builtIn: true,
      description: 'One backward rotation around the phone width.',
      durationMs: 620, exampleCount: 0, family: 'flip', id: 'back-flip', name: 'BACK FLIP',
      rotation: { x: -360, y: 0, z: 0 }, source: 'system',
    },
    {
      aliases: ['FLIP +'], builtIn: true,
      description: 'Long-edge roll in the kickflip direction for the selected grip.',
      durationMs: 600, exampleCount: 0, family: 'flip', id: 'kickflip', name: 'KICKFLIP',
      rotation: { x: 0, y: y(360), z: 0 }, source: 'system',
    },
    {
      aliases: ['FLIP −'], builtIn: true,
      description: 'Long-edge roll in the opposite, heelflip direction.',
      durationMs: 600, exampleCount: 0, family: 'flip', id: 'heelflip', name: 'HEELFLIP',
      rotation: { x: 0, y: y(-360), z: 0 }, source: 'system',
    },
    {
      aliases: ['SHUVIT +'], builtIn: true,
      description: 'Half turn around the screen-normal axis.',
      durationMs: 520, exampleCount: 0, family: 'shuvit', id: 'bs-shuvit', name: 'BACKSIDE SHUVIT',
      rotation: { x: 0, y: 0, z: z(180) }, source: 'system',
    },
    {
      aliases: ['SHUVIT −'], builtIn: true,
      description: 'The opposite half turn around the screen-normal axis.',
      durationMs: 520, exampleCount: 0, family: 'shuvit', id: 'fs-shuvit', name: 'FRONTSIDE SHUVIT',
      rotation: { x: 0, y: 0, z: z(-180) }, source: 'system',
    },
    {
      aliases: [], builtIn: true,
      description: 'Kickflip plus a backside half shuvit.',
      durationMs: 700, exampleCount: 0, family: 'combo', id: 'varial-kickflip', name: 'VARIAL KICKFLIP',
      rotation: { x: 0, y: y(360), z: z(180) }, source: 'system',
    },
    {
      aliases: [], builtIn: true,
      description: 'Heelflip plus a frontside half shuvit.',
      durationMs: 700, exampleCount: 0, family: 'combo', id: 'varial-heelflip', name: 'VARIAL HEELFLIP',
      rotation: { x: 0, y: y(-360), z: z(-180) }, source: 'system',
    },
    {
      aliases: ['KAMIKAZE FLIP'], builtIn: true,
      description: 'House trick: one front flip plus one half flat spin.',
      durationMs: 760, exampleCount: 0, family: 'combo', id: 'kamikaze-flip', name: 'KAMIKAZE FLIP',
      rotation: { x: 360, y: 0, z: z(180) }, source: 'system',
    },
  ];
}

function rotationSimilarity(measured: RotationSummary, target: Vector3): { purity: number; score: number } {
  const targetMagnitude = magnitude(target);
  const measuredVector = { x: measured.x, y: measured.y, z: measured.z };
  const measuredMagnitude = magnitude(measuredVector);
  if (targetMagnitude < 1) {
    return { purity: clamp(1 - measuredMagnitude / 240), score: clamp(1 - measuredMagnitude / 300) };
  }

  const activeAxes = (['x', 'y', 'z'] as const).filter((axis) => Math.abs(target[axis]) >= 1);
  const inactiveAxes = (['x', 'y', 'z'] as const).filter((axis) => Math.abs(target[axis]) < 1);
  const activeError = activeAxes.reduce((sum, axis) =>
    sum + Math.abs(measured[axis] - target[axis]) / Math.max(Math.abs(target[axis]), 180), 0,
  ) / activeAxes.length;
  const crossTalk = inactiveAxes.reduce((sum, axis) => sum + Math.abs(measured[axis]), 0) /
    Math.max(targetMagnitude, 180);
  const purity = clamp(1 - crossTalk);
  return { purity, score: clamp(1 - activeError * 0.72 - crossTalk * 0.28) };
}

export function scoreAttemptAgainstTrick(
  attempt: DetectedAttempt,
  definition: TrickDefinition,
): TrickMatch {
  const similarity = rotationSimilarity(attempt.rotationDegrees, definition.rotation);
  const dynamicSamples = attempt.samples.filter((sample) =>
    Math.hypot(sample.rotationRateDps.x, sample.rotationRateDps.y, sample.rotationRateDps.z) >=
    Math.max(70, attempt.peakRotationDps * 0.14),
  );
  const measuredMotionDurationMs = dynamicSamples.length > 1
    ? (dynamicSamples.at(-1)!.timestampS - dynamicSamples[0].timestampS) * 1000
    : attempt.airtimeMs;
  const timingScore = clamp(1 - Math.abs(measuredMotionDurationMs - definition.durationMs) /
    Math.max(definition.durationMs, 350));
  const landingScore = clamp(1 - Math.max(0, attempt.peakCatchG - 2.7) / 5.5);
  const overallScore = clamp(
    similarity.score * 0.68 + similarity.purity * 0.14 + timingScore * 0.1 + landingScore * 0.08,
  );
  return {
    axisPurity: similarity.purity,
    definition,
    landingScore,
    motionDurationMs: measuredMotionDurationMs,
    overallScore,
    rotationScore: similarity.score,
    timingScore,
  };
}

export function findBestTrickMatch(
  attempt: DetectedAttempt,
  catalog: TrickDefinition[],
): TrickMatch {
  return catalog
    .map((definition) => scoreAttemptAgainstTrick(attempt, definition))
    .sort((left, right) => right.overallScore - left.overallScore)[0];
}

const quantize = (value: number, step: number) => {
  if (Math.abs(value) < step * 0.36) return 0;
  return Math.sign(value) * Math.max(step, Math.round(Math.abs(value) / step) * step);
};

export function inferIdealTrickDefinition(
  name: string,
  attempt: DetectedAttempt,
): TrickDefinition {
  const activeSamples = attempt.samples.filter((sample) =>
    Math.hypot(sample.rotationRateDps.x, sample.rotationRateDps.y, sample.rotationRateDps.z) >=
    Math.max(80, attempt.peakRotationDps * 0.16),
  );
  const activeDurationMs = activeSamples.length > 1
    ? (activeSamples.at(-1)!.timestampS - activeSamples[0].timestampS) * 1000
    : attempt.airtimeMs;
  return {
    aliases: [],
    builtIn: false,
    description: 'Custom ideal inferred from a recorded example. Edit the recipe before saving.',
    durationMs: Math.round(clamp(activeDurationMs, 320, 1800) / 20) * 20,
    exampleCount: 1,
    family: 'custom',
    id: `custom-${Date.now()}`,
    name: name.trim().toUpperCase() || 'UNTITLED TRICK',
    rotation: {
      x: quantize(attempt.rotationDegrees.x, 360),
      y: quantize(attempt.rotationDegrees.y, 360),
      z: quantize(attempt.rotationDegrees.z, 180),
    },
    source: 'recording',
  };
}

export function resolveTrickDefinition(
  name: string,
  catalog: TrickDefinition[],
): TrickDefinition | undefined {
  const normalized = name.trim().toUpperCase();
  return catalog.find((definition) =>
    definition.name === normalized || definition.aliases.some((alias) => alias === normalized),
  );
}
