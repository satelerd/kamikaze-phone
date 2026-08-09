import type {
  DetectedAttempt,
  DetectorSnapshot,
  FlightPhase,
  MotionSample,
  RotationSummary,
  Vector3,
} from './types';

const EARTH_GRAVITY = 9.80665;

export type MotionDetectorConfig = {
  freefallEnterG: number;
  freefallExitG: number;
  minimumFreefallMs: number;
  stableAccelMinG: number;
  stableAccelMaxG: number;
  stableGyroDps: number;
  settleMs: number;
  maximumFlightMs: number;
  preReleaseMs: number;
  gyroEnterDps: number;
  gyroExitDps: number;
  minimumGyroBurstMs: number;
  postMotionMs: number;
};

const DEFAULT_CONFIG: MotionDetectorConfig = {
  freefallEnterG: 0.28,
  freefallExitG: 0.55,
  minimumFreefallMs: 25,
  stableAccelMinG: 0.68,
  stableAccelMaxG: 1.38,
  stableGyroDps: 90,
  settleMs: 180,
  maximumFlightMs: 2600,
  preReleaseMs: 300,
  gyroEnterDps: 180,
  gyroExitDps: 72,
  minimumGyroBurstMs: 18,
  postMotionMs: 220,
};

const zeroVector = (): Vector3 => ({ x: 0, y: 0, z: 0 });

const zeroRotation = (): RotationSummary => ({ x: 0, y: 0, z: 0, total: 0 });

const magnitude = (vector: Vector3): number =>
  Math.sqrt(vector.x ** 2 + vector.y ** 2 + vector.z ** 2);

const clamp = (value: number, minimum: number, maximum: number): number =>
  Math.min(maximum, Math.max(minimum, value));

export function classifyRotation(rotation: RotationSummary): {
  trick: string;
  confidence: number;
} {
  const turns = {
    x: Math.abs(rotation.x) / 360,
    y: Math.abs(rotation.y) / 360,
    z: Math.abs(rotation.z) / 360,
  };
  const dominantTurns = Math.max(turns.x, turns.y, turns.z);

  if (turns.y >= 0.55 && turns.z >= 0.38) {
    return { trick: 'TRE COMBO', confidence: clamp((turns.y + turns.z) / 2, 0.55, 0.98) };
  }

  if (turns.x >= 0.55 && Math.max(turns.y, turns.z) >= 0.22) {
    return { trick: 'KAMIKAZE FLIP', confidence: clamp(turns.x, 0.55, 0.96) };
  }

  if (turns.x >= 0.55) {
    return { trick: rotation.x >= 0 ? 'PHONE FLIP +' : 'PHONE FLIP −', confidence: clamp(turns.x, 0.55, 0.98) };
  }

  if (turns.y >= 0.55) {
    return { trick: rotation.y >= 0 ? 'FLIP +' : 'FLIP −', confidence: clamp(turns.y, 0.55, 0.98) };
  }

  if (turns.z >= 0.38) {
    return { trick: rotation.z >= 0 ? 'SHUVIT +' : 'SHUVIT −', confidence: clamp(turns.z, 0.5, 0.96) };
  }

  return {
    trick: dominantTurns >= 0.18 ? 'AIR MOVE' : 'STRAIGHT AIR',
    confidence: clamp(0.9 - dominantTurns, 0.5, 0.9),
  };
}

export class MotionDetector {
  private readonly config: MotionDetectorConfig;
  private phase: FlightPhase = 'idle';
  private lowGStartedAtS: number | null = null;
  private highGyroStartedAtS: number | null = null;
  private quietStartedAtS: number | null = null;
  private triggerMode: 'freefall' | 'gyro' = 'freefall';
  private releaseTimestampS: number | null = null;
  private catchTimestampS: number | null = null;
  private stableStartedAtS: number | null = null;
  private lastTimestampS: number | null = null;
  private previousRotationRate = zeroVector();
  private rotationDegrees = zeroRotation();
  private sampleCount = 0;
  private peakRotationDps = 0;
  private peakCatchG = 0;
  private accelG = 1;
  private gyroDps = 0;
  private actualHz = 0;
  private lastAttempt: DetectedAttempt | null = null;
  private rollingSamples: MotionSample[] = [];
  private attemptSamples: MotionSample[] = [];
  private attemptSource: DetectedAttempt['source'] = 'sensor';

  constructor(config: Partial<MotionDetectorConfig> = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  arm(source: DetectedAttempt['source'] = 'sensor'): DetectorSnapshot {
    this.phase = 'armed';
    this.lowGStartedAtS = null;
    this.highGyroStartedAtS = null;
    this.quietStartedAtS = null;
    this.triggerMode = 'freefall';
    this.releaseTimestampS = null;
    this.catchTimestampS = null;
    this.stableStartedAtS = null;
    this.lastTimestampS = null;
    this.previousRotationRate = zeroVector();
    this.rotationDegrees = zeroRotation();
    this.sampleCount = 0;
    this.peakRotationDps = 0;
    this.peakCatchG = 0;
    this.rollingSamples = [];
    this.attemptSamples = [];
    this.attemptSource = source;
    return this.snapshot();
  }

  disarm(): DetectorSnapshot {
    this.phase = 'idle';
    this.lowGStartedAtS = null;
    this.stableStartedAtS = null;
    this.attemptSamples = [];
    return this.snapshot();
  }

  process(sample: MotionSample): DetectorSnapshot {
    const dt = this.lastTimestampS === null
      ? 0
      : clamp(sample.timestampS - this.lastTimestampS, 0, 0.05);

    if (dt > 0) {
      const instantaneousHz = 1 / dt;
      this.actualHz = this.actualHz === 0
        ? instantaneousHz
        : this.actualHz * 0.92 + instantaneousHz * 0.08;
    }

    this.lastTimestampS = sample.timestampS;
    this.accelG = magnitude(sample.accelerationIncludingGravity) / EARTH_GRAVITY;
    this.gyroDps = magnitude(sample.rotationRateDps);
    this.pushRollingSample(sample);

    if (this.phase === 'armed') {
      this.detectRelease(sample.timestampS);
    } else if (this.phase === 'airborne') {
      this.appendAttemptSample(sample);
      this.integrateRotation(sample.rotationRateDps, dt);
      this.sampleCount += 1;
      this.peakRotationDps = Math.max(this.peakRotationDps, this.gyroDps);
      this.detectCatch(sample.timestampS);
    } else if (this.phase === 'settling') {
      this.appendAttemptSample(sample);
      this.sampleCount += 1;
      this.peakCatchG = Math.max(this.peakCatchG, this.accelG);
      this.detectSettled(sample.timestampS);
    }

    this.previousRotationRate = sample.rotationRateDps;
    return this.snapshot();
  }

  private detectRelease(timestampS: number): void {
    if (this.accelG <= this.config.freefallEnterG) {
      this.highGyroStartedAtS = null;
      if (this.lowGStartedAtS === null) this.lowGStartedAtS = timestampS;
      const lowGDurationMs = (timestampS - this.lowGStartedAtS) * 1000;
      if (lowGDurationMs >= this.config.minimumFreefallMs) {
        this.beginAttempt(this.lowGStartedAtS, timestampS, 'freefall');
      }
      return;
    }

    this.lowGStartedAtS = null;
    if (this.gyroDps < this.config.gyroEnterDps) {
      this.highGyroStartedAtS = null;
      return;
    }
    if (this.highGyroStartedAtS === null) {
      this.highGyroStartedAtS = timestampS;
      return;
    }
    if ((timestampS - this.highGyroStartedAtS) * 1000 >= this.config.minimumGyroBurstMs) {
      this.beginAttempt(
        Math.max(this.rollingSamples[0]?.timestampS ?? this.highGyroStartedAtS, this.highGyroStartedAtS - 0.12),
        timestampS,
        'gyro',
      );
    }
  }

  private beginAttempt(releaseTimestampS: number, confirmedAtS: number, triggerMode: 'freefall' | 'gyro'): void {
    this.phase = 'airborne';
    this.triggerMode = triggerMode;
    this.releaseTimestampS = releaseTimestampS;
    this.quietStartedAtS = null;
    this.attemptSamples = this.rollingSamples.filter((sample) =>
      sample.timestampS >= releaseTimestampS - this.config.preReleaseMs / 1000,
    );
    this.rebuildAirborneMetrics(confirmedAtS);
  }

  private pushRollingSample(sample: MotionSample): void {
    this.rollingSamples.push(sample);
    const cutoff = sample.timestampS - (this.config.preReleaseMs + this.config.minimumFreefallMs + 50) / 1000;
    while (this.rollingSamples.length > 0 && this.rollingSamples[0].timestampS < cutoff) {
      this.rollingSamples.shift();
    }
  }

  private appendAttemptSample(sample: MotionSample): void {
    const lastSample = this.attemptSamples[this.attemptSamples.length - 1];
    if (!lastSample || lastSample.timestampS !== sample.timestampS) {
      this.attemptSamples.push(sample);
    }
  }

  private rebuildAirborneMetrics(confirmedAtS: number): void {
    if (this.releaseTimestampS === null) return;

    const airborneSamples = this.attemptSamples.filter((sample) =>
      sample.timestampS >= this.releaseTimestampS! && sample.timestampS <= confirmedAtS,
    );
    this.rotationDegrees = zeroRotation();
    this.sampleCount = airborneSamples.length;
    this.peakRotationDps = 0;

    let previous: MotionSample | null = null;
    airborneSamples.forEach((sample) => {
      const sampleGyro = magnitude(sample.rotationRateDps);
      this.peakRotationDps = Math.max(this.peakRotationDps, sampleGyro);
      if (previous) {
        const dt = clamp(sample.timestampS - previous.timestampS, 0, 0.05);
        this.previousRotationRate = previous.rotationRateDps;
        this.integrateRotation(sample.rotationRateDps, dt);
      }
      previous = sample;
    });

    this.previousRotationRate = airborneSamples[airborneSamples.length - 1]?.rotationRateDps ?? zeroVector();
  }

  private integrateRotation(rotationRate: Vector3, dt: number): void {
    if (dt <= 0) return;

    const average = {
      x: (this.previousRotationRate.x + rotationRate.x) / 2,
      y: (this.previousRotationRate.y + rotationRate.y) / 2,
      z: (this.previousRotationRate.z + rotationRate.z) / 2,
    };

    this.rotationDegrees.x += average.x * dt;
    this.rotationDegrees.y += average.y * dt;
    this.rotationDegrees.z += average.z * dt;
    this.rotationDegrees.total += magnitude(average) * dt;
  }

  private detectCatch(timestampS: number): void {
    if (this.releaseTimestampS === null) return;

    const flightDurationMs = (timestampS - this.releaseTimestampS) * 1000;
    if (this.triggerMode === 'gyro') {
      const isDynamic = this.gyroDps >= this.config.gyroExitDps ||
        this.accelG < 0.55 ||
        this.accelG > 1.55;
      if (isDynamic && flightDurationMs < this.config.maximumFlightMs) {
        this.quietStartedAtS = null;
        return;
      }
      if (this.quietStartedAtS === null) {
        this.quietStartedAtS = timestampS;
        return;
      }
      if ((timestampS - this.quietStartedAtS) * 1000 < this.config.postMotionMs &&
          flightDurationMs < this.config.maximumFlightMs) return;
      this.phase = 'settling';
      this.catchTimestampS = timestampS;
      this.stableStartedAtS = null;
      this.peakCatchG = this.accelG;
      return;
    }

    if (this.accelG >= this.config.freefallExitG || flightDurationMs >= this.config.maximumFlightMs) {
      this.phase = 'settling';
      this.catchTimestampS = timestampS;
      this.stableStartedAtS = null;
      this.peakCatchG = this.accelG;
    }
  }

  private detectSettled(timestampS: number): void {
    if (this.triggerMode === 'gyro') {
      const resumed = this.gyroDps >= this.config.gyroExitDps || this.accelG < 0.55 || this.accelG > 1.55;
      if (resumed) {
        this.phase = 'airborne';
        this.catchTimestampS = null;
        this.stableStartedAtS = null;
        this.quietStartedAtS = null;
        return;
      }
    }
    if (this.accelG < this.config.freefallEnterG) {
      this.phase = 'airborne';
      this.catchTimestampS = null;
      this.stableStartedAtS = null;
      return;
    }

    const isStable =
      this.accelG >= this.config.stableAccelMinG &&
      this.accelG <= this.config.stableAccelMaxG &&
      this.gyroDps <= this.config.stableGyroDps;

    if (!isStable) {
      this.stableStartedAtS = null;
      return;
    }

    if (this.stableStartedAtS === null) {
      this.stableStartedAtS = timestampS;
      return;
    }

    if ((timestampS - this.stableStartedAtS) * 1000 >= this.config.settleMs) {
      this.completeAttempt();
    }
  }

  private completeAttempt(): void {
    if (this.releaseTimestampS === null || this.catchTimestampS === null) return;

    const airtimeMs = Math.max(0, (this.catchTimestampS - this.releaseTimestampS) * 1000);
    const airtimeS = airtimeMs / 1000;
    const classification = classifyRotation(this.rotationDegrees);

    this.lastAttempt = {
      id: `${Date.now()}-${Math.round(this.releaseTimestampS * 1000)}`,
      captureMode: 'auto',
      triggerMode: this.triggerMode,
      schemaVersion: 2,
      source: this.attemptSource,
      recordedAtIso: new Date().toISOString(),
      trick: classification.trick,
      confidence: classification.confidence,
      releaseTimestampS: this.releaseTimestampS,
      catchTimestampS: this.catchTimestampS,
      airtimeMs,
      estimatedHeightM: this.triggerMode === 'freefall' ? EARTH_GRAVITY * airtimeS ** 2 / 8 : 0,
      rotationDegrees: { ...this.rotationDegrees },
      peakRotationDps: this.peakRotationDps,
      peakCatchG: this.peakCatchG,
      sampleCount: this.sampleCount,
      samples: this.attemptSamples.map((sample) => ({
        ...sample,
        accelerationIncludingGravity: { ...sample.accelerationIncludingGravity },
        rotationRateDps: { ...sample.rotationRateDps },
      })),
    };
    this.phase = 'complete';
  }

  private snapshot(): DetectorSnapshot {
    return {
      phase: this.phase,
      accelG: this.accelG,
      gyroDps: this.gyroDps,
      actualHz: this.actualHz,
      rotationDegrees: { ...this.rotationDegrees },
      sampleCount: this.sampleCount,
      lastAttempt: this.lastAttempt,
    };
  }
}

export function makeSyntheticThrowSamples(options: {
  airtimeMs?: number;
  rotationDps?: Vector3;
  sampleRateHz?: number;
} = {}): MotionSample[] {
  const airtimeMs = options.airtimeMs ?? 920;
  const rotationDps = options.rotationDps ?? { x: 410, y: 60, z: 20 };
  const sampleRateHz = options.sampleRateHz ?? 100;
  const stepS = 1 / sampleRateHz;
  const samples: MotionSample[] = [];
  let timestampS = 100;

  const pushFor = (durationMs: number, accelG: number, rotationRateDps: Vector3) => {
    const count = Math.ceil(durationMs / 1000 * sampleRateHz);
    for (let index = 0; index < count; index += 1) {
      samples.push({
        timestampS,
        accelerationIncludingGravity: { x: 0, y: 0, z: accelG * EARTH_GRAVITY },
        rotationRateDps,
      });
      timestampS += stepS;
    }
  };

  pushFor(180, 1, zeroVector());
  pushFor(airtimeMs, 0.04, rotationDps);
  pushFor(40, 2.1, { x: 120, y: 20, z: 10 });
  pushFor(320, 1, zeroVector());
  return samples;
}
