'use client';

// Camera + recorder rig for the Trick Lab.
// - getUserMedia asking for 120 fps (falls back to whatever the camera grants)
// - per-attempt front/back camera choice (mobile browsers cannot stream both)
// - anti motion blur: locks a short manual exposure when the track supports it
// - MediaRecorder with a performance.now() start timestamp for IMU/video sync
import { useCallback, useEffect, useRef, useState } from 'react';
import type { CameraFacing, CaptureInfo } from './labTypes';

/** Non-standard image-capture capabilities (Android Chrome exposes these). */
interface ExposureCapabilities {
  exposureMode?: string[];
  exposureTime?: { min: number; max: number; step?: number };
}

const MIME_CANDIDATES = [
  'video/webm;codecs=vp9',
  'video/webm;codecs=vp8',
  'video/webm',
  'video/mp4;codecs=avc1.42E01E',
  'video/mp4',
];

function pickMime(): string {
  if (typeof MediaRecorder === 'undefined') return '';
  return MIME_CANDIDATES.find((m) => MediaRecorder.isTypeSupported(m)) ?? '';
}

export interface RecordedClip {
  blob: Blob;
  mimeType: string;
}

export function useVideoRig() {
  const [stream, setStream] = useState<MediaStream | null>(null);
  const [capture, setCapture] = useState<CaptureInfo | null>(null);
  const [error, setError] = useState<string | null>(null);

  const streamRef = useRef<MediaStream | null>(null);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const recStartPerfRef = useRef<number>(NaN);

  const close = useCallback(() => {
    const rec = recorderRef.current;
    if (rec && rec.state !== 'inactive') {
      try { rec.stop(); } catch { /* already gone */ }
    }
    recorderRef.current = null;
    chunksRef.current = [];
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    setStream(null);
    setCapture(null);
  }, []);

  const open = useCallback(async (facing: CameraFacing): Promise<boolean> => {
    close();
    setError(null);
    try {
      const media = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: {
          facingMode: facing,
          // Ask big: Pixel 9 / iPhone keep what they can honor, ideal never rejects.
          frameRate: { ideal: 120 },
          width: { ideal: 1280 },
          height: { ideal: 720 },
        },
      });
      const track = media.getVideoTracks()[0];

      // Anti motion blur: if the camera exposes manual exposure, lock a short
      // shutter (~5 ms). Where it does not (iOS Safari), the pre-record tips
      // UI tells the rider to find bright light instead.
      let exposureLocked = false;
      const caps = (track.getCapabilities?.() ?? {}) as ExposureCapabilities;
      if (caps.exposureMode?.includes('manual') && caps.exposureTime) {
        // exposureTime is in 100 µs units per the mediacapture-image spec.
        const target = Math.min(Math.max(50, caps.exposureTime.min), caps.exposureTime.max);
        try {
          await track.applyConstraints({
            advanced: [
              { exposureMode: 'manual', exposureTime: target } as MediaTrackConstraintSet,
            ],
          });
          exposureLocked = true;
        } catch {
          // Camera refused manual exposure: stay on auto, tips UI covers it.
        }
      }

      const settings = track.getSettings();
      streamRef.current = media;
      setStream(media);
      setCapture({
        width: settings.width ?? 1280,
        height: settings.height ?? 720,
        fps: Math.round(settings.frameRate ?? 30),
        facing,
        exposureLocked,
        mimeType: pickMime(),
      });
      return true;
    } catch {
      setError('Camera said no. Check browser permissions and try again. 📷');
      return false;
    }
  }, [close]);

  /** Start recording the open stream. Returns false when recording is impossible. */
  const startRecording = useCallback((): boolean => {
    const media = streamRef.current;
    if (!media || typeof MediaRecorder === 'undefined') {
      setError('This browser cannot record video (no MediaRecorder). 🎬');
      return false;
    }
    try {
      const mimeType = pickMime();
      const rec = new MediaRecorder(
        media,
        mimeType ? { mimeType, videoBitsPerSecond: 8_000_000 } : { videoBitsPerSecond: 8_000_000 },
      );
      chunksRef.current = [];
      rec.ondataavailable = (e: BlobEvent) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };
      recorderRef.current = rec;
      rec.start();
      // First encoded frame lands within a few ms of start(); the review flow
      // adds pre-roll margin around the flight window to absorb the jitter.
      recStartPerfRef.current = performance.now();
      return true;
    } catch {
      setError('Recording failed to start. The camera may be busy. 🎬');
      return false;
    }
  }, []);

  /** Stop the recorder and hand back the clip. Null when nothing was captured. */
  const stopRecording = useCallback((): Promise<RecordedClip | null> => {
    const rec = recorderRef.current;
    if (!rec || rec.state === 'inactive') return Promise.resolve(null);
    return new Promise((resolve) => {
      rec.onstop = () => {
        recorderRef.current = null;
        const mimeType = rec.mimeType || 'video/webm';
        const blob = new Blob(chunksRef.current, { type: mimeType });
        chunksRef.current = [];
        resolve(blob.size > 0 ? { blob, mimeType } : null);
      };
      try {
        rec.stop();
      } catch {
        recorderRef.current = null;
        resolve(null);
      }
    });
  }, []);

  const recStartPerf = useCallback(() => recStartPerfRef.current, []);

  useEffect(() => close, [close]);

  return { stream, capture, error, open, close, startRecording, stopRecording, recStartPerf };
}
