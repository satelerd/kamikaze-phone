// Frame extraction: pull canvas frames out of the recorded clip at chosen video
// times (for the 3D frusta cards + the DA3 export), plus gradient placeholder
// frames for the desktop demo where no clip exists.
//
// Chrome gotcha: MediaRecorder webm blobs report `duration = Infinity` until
// you force a seek far past the end. openClip() handles that dance.
import type { FrameSample } from './labTypes';

const FRAME_W = 480;

function waitEvent(v: HTMLVideoElement, ev: string, timeoutMs: number): Promise<void> {
  return new Promise((resolve) => {
    let settled = false;
    const finish = () => {
      if (settled) return;
      settled = true;
      v.removeEventListener(ev, finish);
      clearTimeout(timer);
      resolve();
    };
    const timer = setTimeout(finish, timeoutMs);
    v.addEventListener(ev, finish);
  });
}

/** Load a clip into an off-DOM video element that is actually seekable. */
export async function openClip(url: string): Promise<HTMLVideoElement> {
  const v = document.createElement('video');
  v.src = url;
  v.muted = true;
  v.playsInline = true;
  v.preload = 'auto';
  v.load();
  await waitEvent(v, 'loadedmetadata', 4000);
  if (!Number.isFinite(v.duration)) {
    // Force Chrome to resolve the real duration of a MediaRecorder webm.
    v.currentTime = 1e7;
    await waitEvent(v, 'seeked', 2500);
    v.currentTime = 0;
    await waitEvent(v, 'seeked', 1500);
  }
  return v;
}

export interface FrameRequest {
  videoTimeSec: number;
  /** ms relative to launch, carried through to the FrameSample */
  tMs: number;
}

/** Evenly sample `count` frame times across the flight window. */
export function planFrameTimes(
  launchVideoSec: number,
  landVideoSec: number,
  count: number,
): FrameRequest[] {
  const start = Math.max(0, launchVideoSec);
  const span = Math.max(0.05, landVideoSec - start);
  const out: FrameRequest[] = [];
  for (let i = 0; i < count; i++) {
    const f = count === 1 ? 0.5 : i / (count - 1);
    out.push({ videoTimeSec: start + span * f, tMs: span * f * 1000 });
  }
  return out;
}

/** Seek + draw each requested time. Returns whatever frames actually decoded. */
export async function extractFrames(
  url: string,
  requests: FrameRequest[],
): Promise<FrameSample[]> {
  const v = await openClip(url);
  const out: FrameSample[] = [];
  try {
    const dur = Number.isFinite(v.duration) ? v.duration : Number.POSITIVE_INFINITY;
    for (const req of requests) {
      const t = Math.max(0, Math.min(req.videoTimeSec, dur - 0.03));
      v.currentTime = t;
      await waitEvent(v, 'seeked', 1200);
      const w = v.videoWidth;
      const h = v.videoHeight;
      if (!w || !h) continue;
      const canvas = document.createElement('canvas');
      canvas.width = FRAME_W;
      canvas.height = Math.max(2, Math.round((h / w) * FRAME_W));
      const ctx = canvas.getContext('2d');
      if (!ctx) continue;
      try {
        ctx.drawImage(v, 0, 0, canvas.width, canvas.height);
      } catch {
        continue;
      }
      out.push({ tMs: req.tMs, videoTimeSec: t, canvas, placeholder: false });
    }
  } finally {
    v.removeAttribute('src');
    v.load();
  }
  return out;
}

/** Gradient stand-in frames for the desktop demo (no camera, no clip). */
export function placeholderFrames(count: number, flightMs: number): FrameSample[] {
  const out: FrameSample[] = [];
  const H = 270;
  for (let i = 0; i < count; i++) {
    const tMs = (Math.max(1, flightMs) * i) / Math.max(1, count - 1);
    const canvas = document.createElement('canvas');
    canvas.width = FRAME_W;
    canvas.height = H;
    const ctx = canvas.getContext('2d');
    if (ctx) {
      const grad = ctx.createLinearGradient(0, 0, FRAME_W, H);
      grad.addColorStop(0, `hsl(${38 + i * 16} 92% 55%)`);
      grad.addColorStop(1, `hsl(${255 + i * 6} 65% 20%)`);
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, FRAME_W, H);
      ctx.fillStyle = 'rgba(9, 9, 11, 0.55)';
      ctx.fillRect(0, H - 64, FRAME_W, 64);
      ctx.fillStyle = '#fafafa';
      ctx.font = 'bold 46px system-ui, sans-serif';
      ctx.fillText(`SIM ${i + 1}`, 18, 58);
      ctx.fillStyle = '#fbbf24';
      ctx.font = 'bold 24px system-ui, sans-serif';
      ctx.fillText(`t = ${(tMs / 1000).toFixed(2)}s`, 18, H - 22);
    }
    out.push({ tMs, videoTimeSec: -1, canvas, placeholder: true });
  }
  return out;
}
