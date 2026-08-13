// Trick Lab local types: capture metadata, extracted frames, finished takes.
import type { TrickResult } from '@/lib/types';

export type CameraFacing = 'environment' | 'user';

export interface CaptureInfo {
  width: number;
  height: number;
  /** frames per second the camera actually granted (we ask for 120) */
  fps: number;
  facing: CameraFacing;
  /** true when we managed to lock a short manual exposure via applyConstraints */
  exposureLocked: boolean;
  mimeType: string;
}

export interface FrameSample {
  /** ms relative to launch */
  tMs: number;
  /** video currentTime (seconds) this frame was pulled from; -1 for placeholders */
  videoTimeSec: number;
  canvas: HTMLCanvasElement;
  placeholder: boolean;
}

/** One finished Trick Lab attempt: score + clip + frames, ready for review. */
export interface LabTake {
  result: TrickResult;
  /** blob URL of the recorded clip; null in desktop demo mode */
  videoUrl: string | null;
  videoBlob: Blob | null;
  capture: CaptureInfo | null;
  /** launch / land moments in video time (seconds); NaN when no video */
  launchVideoSec: number;
  landVideoSec: number;
  frames: FrameSample[];
}
