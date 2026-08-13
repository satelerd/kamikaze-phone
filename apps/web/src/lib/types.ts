// Shared types for the Kamikaze Phone engine.

/** One IMU sample in device frame. Units: m/s² and deg/s. */
export interface IMUSample {
  /** ms since session start */
  t: number;
  /** acceleration including gravity (device frame) */
  ax: number;
  ay: number;
  az: number;
  /** linear acceleration (gravity removed) when available */
  lx: number;
  ly: number;
  lz: number;
  /** rotation rate deg/s: alpha (z), beta (x), gamma (y) */
  rz: number;
  rx: number;
  ry: number;
}

export interface MagSample {
  t: number;
  x: number;
  y: number;
  z: number;
  /** magnitude in µT */
  mag: number;
}

export interface LuxSample {
  t: number;
  lux: number;
}

export type ThrowPhase = 'idle' | 'windup' | 'airborne' | 'impact' | 'held';

export interface TrajectoryPoint {
  /** ms relative to launch */
  t: number;
  /** world-frame position (m); origin = launch point, +y up */
  x: number;
  y: number;
  z: number;
  /** device orientation quaternion */
  qx: number;
  qy: number;
  qz: number;
  qw: number;
}

export interface TrickFeatures {
  /** seconds in freefall */
  airtime: number;
  /** peak height above launch (m), h = g·T²/8 */
  height: number;
  /** total signed rotation per device axis during flight (degrees) */
  rotX: number;
  rotY: number;
  rotZ: number;
  /** 0..1: how much of total rotation is on the dominant axis */
  axisPurity: number;
  dominantAxis: 'x' | 'y' | 'z';
  /** gyro variance during flight (wobble) */
  wobble: number;
  /** peak |a| at catch (m/s²) */
  impactG: number;
  /** ms from impact until device is stable again */
  settleMs: number;
  /** launch speed estimate from windup integration (m/s) */
  launchSpeed: number;
  /** whether the phone was caught (stabilized) vs dropped (multi-impact) */
  caught: boolean;
}

export interface StyleScore {
  amplitude: number;
  rotation: number;
  cleanliness: number;
  catch: number;
  commitment: number;
}

export interface TrickResult {
  id: string;
  /** trick library id, e.g. 'pancake-double' */
  trickId: string;
  trickName: string;
  /** flavor line for the narrator */
  callout: string;
  features: TrickFeatures;
  style: StyleScore;
  /** 0..100 weighted total */
  score: number;
  grade: 'S' | 'A' | 'B' | 'C' | 'BAIL';
  trajectory: TrajectoryPoint[];
  at: number;
  mode: string;
}

export type CapabilityKey =
  | 'motion'
  | 'magnetometer'
  | 'ambientLight'
  | 'torch'
  | 'vibration'
  | 'battery'
  | 'nfc'
  | 'microphone'
  | 'camera'
  | 'speech'
  | 'webrtc'
  | 'wakeLock';

export type CapabilityState = 'yes' | 'no' | 'needs-permission' | 'unknown';

export type CapabilityReport = Record<CapabilityKey, CapabilityState>;

export type DevicePresetId = 'pixel-9' | 'iphone' | 'android' | 'desktop';

export interface ModeDefinition {
  id: string;
  title: string;
  tagline: string;
  emoji: string;
  path: string;
  /** capabilities required to actually play */
  requires: CapabilityKey[];
  /** capabilities that improve the mode but have fallbacks */
  enhancedBy: CapabilityKey[];
  /** shown when a required capability is missing */
  lockedHint?: string;
}

export interface AchievementDef {
  id: string;
  name: string;
  description: string;
  emoji: string;
  /** which mode usually unlocks it */
  mode?: string;
  secret?: boolean;
}

export type GameEvent =
  | { type: 'countdown-tick'; n: number }
  | { type: 'launch' }
  | { type: 'flip'; count: number }
  | { type: 'peak'; height: number }
  | { type: 'catch'; clean: boolean; impactG: number }
  | { type: 'bail' }
  | { type: 'grind-start' }
  | { type: 'grind-tick'; intensity: number }
  | { type: 'grind-end'; ms: number }
  | { type: 'trick'; result: TrickResult }
  | { type: 'achievement'; id: string }
  | { type: 'ui-select' }
  | { type: 'ui-start' };
