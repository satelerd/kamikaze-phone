// "Export DA3 bundle": one JSON file with trajectory poses, timestamps, an
// intrinsics guess and up to 12 JPEG frames, shaped for the nano-world-model
// video_to_3d workflow. Full format + pipeline docs live in docs/VIDEO-TO-3D.md.
import type { TrickResult } from '@/lib/types';
import type { CaptureInfo, FrameSample } from './labTypes';

const MAX_EXPORT_FRAMES = 12;
/** Typical smartphone main-camera horizontal FOV guess (degrees). */
const HFOV_GUESS_DEG = 68;

export function buildDA3Bundle(
  result: TrickResult,
  frames: FrameSample[],
  capture: CaptureInfo | null,
): Record<string, unknown> {
  const width = capture?.width ?? 1280;
  const height = capture?.height ?? 720;
  const fx = width / 2 / Math.tan((HFOV_GUESS_DEG * Math.PI) / 360);

  return {
    format: 'kamikaze-da3-bundle',
    version: 1,
    generator: 'kamikaze-phone trick-lab',
    exportedAt: new Date().toISOString(),
    trick: {
      id: result.trickId,
      name: result.trickName,
      grade: result.grade,
      score: result.score,
      airtimeSec: result.features.airtime,
      heightM: result.features.height,
      rotationDeg: { x: result.features.rotX, y: result.features.rotY, z: result.features.rotZ },
    },
    capture: capture
      ? {
          widthPx: capture.width,
          heightPx: capture.height,
          fps: capture.fps,
          facing: capture.facing,
          exposureLocked: capture.exposureLocked,
          mimeType: capture.mimeType,
        }
      : null,
    intrinsicsGuess: {
      model: 'pinhole',
      note:
        `Guessed from a ${HFOV_GUESS_DEG} degree horizontal FOV assumption, not calibrated. ` +
        'For real reconstructions let DA3 estimate intrinsics from the video itself.',
      widthPx: width,
      heightPx: height,
      fx,
      fy: fx,
      cx: width / 2,
      cy: height / 2,
    },
    coordinateFrame: {
      origin: 'launch point',
      up: '+y',
      units: 'meters',
      quaternions: 'device orientation from gyro integration, order [x, y, z, w]',
      timebase: 'tMs is milliseconds since launch',
    },
    poses: result.trajectory.map((p) => ({
      tMs: p.t,
      position: [p.x, p.y, p.z],
      quaternionXYZW: [p.qx, p.qy, p.qz, p.qw],
    })),
    frames: frames.slice(0, MAX_EXPORT_FRAMES).map((f, index) => ({
      index,
      tMs: Math.round(f.tMs),
      videoTimeSec: f.videoTimeSec >= 0 ? Number(f.videoTimeSec.toFixed(3)) : null,
      placeholder: f.placeholder,
      jpegBase64: f.canvas.toDataURL('image/jpeg', 0.72).split(',')[1] ?? '',
    })),
  };
}

function triggerDownload(url: string, filename: string): void {
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
}

export function downloadBundle(
  result: TrickResult,
  frames: FrameSample[],
  capture: CaptureInfo | null,
): void {
  const bundle = buildDA3Bundle(result, frames, capture);
  const blob = new Blob([JSON.stringify(bundle, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  triggerDownload(url, `kamikaze-da3-${result.trickId}-${result.at}.json`);
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

/** Save the raw clip so the real DA3 pipeline can chew on it (see docs). */
export function downloadClip(blob: Blob, mimeType: string, result: TrickResult): void {
  const ext = mimeType.includes('mp4') ? 'mp4' : 'webm';
  const url = URL.createObjectURL(blob);
  triggerDownload(url, `kamikaze-clip-${result.trickId}-${result.at}.${ext}`);
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}
