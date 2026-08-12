export type Vector3 = {
  x: number;
  y: number;
  z: number;
};

export type MotionSample = {
  timestampS: number;
  accelerationIncludingGravity: Vector3;
  rotationRateDps: Vector3;
};

export type Quaternion = {
  w: number;
  x: number;
  y: number;
  z: number;
};

export type ReplayFrame = {
  timestampMs: number;
  progress: number;
  quaternion: Quaternion;
  accelG: number;
  gyroDps: number;
};

export type FlightPhase = 'idle' | 'armed' | 'airborne' | 'settling' | 'complete';

export type RotationSummary = Vector3 & {
  total: number;
};

export type DetectedAttempt = {
  captureMode?: 'auto' | 'manual';
  triggerMode?: 'freefall' | 'gyro';
  id: string;
  schemaVersion: 2;
  source: 'sensor' | 'synthetic';
  recordedAtIso: string;
  trick: string;
  confidence: number;
  releaseTimestampS: number;
  catchTimestampS: number;
  airtimeMs: number;
  estimatedHeightM: number;
  rotationDegrees: RotationSummary;
  peakRotationDps: number;
  peakCatchG: number;
  sampleCount: number;
  samples: MotionSample[];
};

export type DetectorSnapshot = {
  phase: FlightPhase;
  accelG: number;
  gyroDps: number;
  actualHz: number;
  rotationDegrees: RotationSummary;
  sampleCount: number;
  lastAttempt: DetectedAttempt | null;
};
