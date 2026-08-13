'use client';

// Trick Lab: slow-mo video of every trick + DA3-style 3D reconstruction.
// Flow: intro (camera pick + light tips) → armed (recording + IMU tracking)
// → processing (classify, trim, extract frames) → review (replay + 3D + export).
// Desktop demo: no sensors needed, a simulated throw runs the same pipeline.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { classifyThrow } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import { recordTrick } from '@/lib/store';
import { detectCapabilities } from '@/lib/capabilities';
import TrajectoryViewer from '@/components/TrajectoryViewer';
import { useTrickSession, type ThrowCapture } from './useTrickSession';
import { useVideoRig } from './useVideoRig';
import { useWakeLock } from './useWakeLock';
import { extractFrames, placeholderFrames, planFrameTimes } from './frames';
import { downloadBundle, downloadClip } from './exportBundle';
import SlowMoPlayer from './SlowMoPlayer';
import ResultCard from './ResultCard';
import type { CameraFacing, FrameSample, LabTake } from './labTypes';

type Phase = 'intro' | 'armed' | 'processing' | 'review';

const FRAME_COUNT = 12;

export default function TrickLab() {
  const [phase, setPhase] = useState<Phase>('intro');
  const [facing, setFacing] = useState<CameraFacing>('environment');
  const [take, setTake] = useState<LabTake | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [demoBusy, setDemoBusy] = useState(false);
  const [demoAvailable, setDemoAvailable] = useState(false);
  const [torchState, setTorchState] = useState<'off' | 'on' | 'nope'>('off');

  const previewRef = useRef<HTMLVideoElement | null>(null);
  const playheadMsRef = useRef(0);
  const processingRef = useRef(false);
  const phaseRef = useRef<Phase>('intro');
  phaseRef.current = phase;

  const rig = useVideoRig();
  const handleThrowRef = useRef<(t: ThrowCapture) => void>(() => {});
  const session = useTrickSession((t) => handleThrowRef.current(t));

  useWakeLock(phase === 'armed' || phase === 'processing');

  useEffect(() => {
    // Desktop / denied sensors: offer the simulated throw path.
    setDemoAvailable(detectCapabilities().motion === 'no');
  }, []);

  // Attach the live camera preview while armed.
  useEffect(() => {
    const v = previewRef.current;
    if (!v || !rig.stream) return;
    v.srcObject = rig.stream;
    void v.play().catch(() => undefined);
    return () => {
      v.srcObject = null;
    };
  }, [rig.stream, phase]);

  // Revoke the previous clip URL whenever the take changes (and on unmount).
  useEffect(() => {
    const url = take?.videoUrl;
    return () => {
      if (url) URL.revokeObjectURL(url);
    };
  }, [take]);

  const processThrow = useCallback(
    async (t: ThrowCapture) => {
      if (processingRef.current) return;
      if (!t.simulated && phaseRef.current !== 'armed') return;
      processingRef.current = true;
      setPhase('processing');
      session.stop();

      const result = classifyThrow(t.rec, 'trick-lab');
      recordTrick(result);
      FXEngine.handle({ type: 'trick', result });
      const flightMs = Math.max(1, t.rec.landT - t.rec.launchT);

      if (t.simulated) {
        setTake({
          result,
          videoUrl: null,
          videoBlob: null,
          capture: null,
          launchVideoSec: NaN,
          landVideoSec: NaN,
          frames: placeholderFrames(10, flightMs),
        });
        setPhase('review');
        setDemoBusy(false);
        processingRef.current = false;
        return;
      }

      // Let the catch aftermath land on tape before cutting.
      await new Promise((r) => setTimeout(r, 350));
      const clip = await rig.stopRecording();
      const recStart = rig.recStartPerf();
      rig.close();
      setTorchState('off');

      let videoUrl: string | null = null;
      let launchVideoSec = NaN;
      let landVideoSec = NaN;
      let frames: FrameSample[] = [];
      if (clip && Number.isFinite(recStart)) {
        videoUrl = URL.createObjectURL(clip.blob);
        launchVideoSec = (t.launchPerf - recStart) / 1000;
        landVideoSec = (t.landPerf - recStart) / 1000;
        try {
          frames = await extractFrames(
            videoUrl,
            planFrameTimes(launchVideoSec, landVideoSec, FRAME_COUNT),
          );
        } catch {
          frames = [];
        }
      }
      if (frames.length === 0) frames = placeholderFrames(10, flightMs);

      setTake({
        result,
        videoUrl,
        videoBlob: clip?.blob ?? null,
        capture: rig.capture,
        launchVideoSec,
        landVideoSec,
        frames,
      });
      setPhase('review');
      processingRef.current = false;
    },
    [rig, session],
  );
  handleThrowRef.current = (t) => void processThrow(t);

  const fireUp = useCallback(async () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    setNotice(null);
    setTorchState('off');
    const motionOk = await SensorEngine.get().requestPermission();
    if (!motionOk) {
      setNotice('Motion sensors said no. Check browser settings, or run a simulated throw. ⚠️');
      setDemoAvailable(true);
      return;
    }
    const camOk = await rig.open(facing);
    if (!camOk) return; // rig.error carries the message
    SensorEngine.get().start();
    session.start();
    if (!rig.startRecording()) {
      rig.close();
      session.stop();
      return;
    }
    setPhase('armed');
  }, [facing, rig, session]);

  const cancel = useCallback(async () => {
    session.stop();
    await rig.stopRecording(); // discard
    rig.close();
    setTorchState('off');
    setPhase('intro');
  }, [rig, session]);

  const runDemo = useCallback(async () => {
    if (demoBusy || processingRef.current) return;
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    setNotice(null);
    setDemoBusy(true);
    session.start();
    await session.simulate();
    // The throw lands via the session callback; this is just a safety net.
    setTimeout(() => setDemoBusy(false), 1500);
  }, [demoBusy, session]);

  const torchFx = useCallback(async () => {
    const ok = await FXEngine.enableTorch();
    setTorchState(ok ? 'on' : 'nope');
  }, []);

  const newThrow = useCallback(() => {
    FXEngine.handle({ type: 'ui-select' });
    setTake(null);
    setPhase('intro');
  }, []);

  // Stable identity: the viewer rebuilds its scene when this array changes.
  const viewerFrames = useMemo(
    () => (take ? take.frames.map((f) => ({ tMs: f.tMs, image: f.canvas })) : []),
    [take],
  );

  // ------------------------------------------------------------------ render
  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-8">
      <header className="mb-6 flex items-center justify-between">
        <Link href="/" className="text-sm text-zinc-400 underline underline-offset-4">
          ← Home
        </Link>
        <span className="text-sm text-zinc-500">Trick Lab 🎥</span>
      </header>

      {phase === 'intro' && (
        <section>
          <h1 className="text-3xl font-black">
            Trick Lab <span className="text-amber-400">🎥</span>
          </h1>
          <p className="mt-2 text-zinc-400">
            Slow-mo replay plus a full 3D rebuild of every trick. Science, but gnarly. 🤙
          </p>

          <div className="mt-6">
            <p className="text-sm font-bold text-zinc-300">Pick your angle</p>
            <div className="mt-2 grid grid-cols-2 gap-3">
              <button
                onClick={() => {
                  setFacing('environment');
                  FXEngine.handle({ type: 'ui-select' });
                }}
                className={`rounded-2xl border p-4 text-left active:scale-95 ${
                  facing === 'environment'
                    ? 'border-amber-400 bg-amber-400/10'
                    : 'border-zinc-700 bg-zinc-900'
                }`}
              >
                <div className="text-2xl">🔭</div>
                <div className="mt-1 font-bold">Back camera</div>
                <div className="mt-1 text-xs text-zinc-400">
                  Prop the phone up, film your buddy throwing theirs.
                </div>
              </button>
              <button
                onClick={() => {
                  setFacing('user');
                  FXEngine.handle({ type: 'ui-select' });
                }}
                className={`rounded-2xl border p-4 text-left active:scale-95 ${
                  facing === 'user' ? 'border-amber-400 bg-amber-400/10' : 'border-zinc-700 bg-zinc-900'
                }`}
              >
                <div className="text-2xl">🤳</div>
                <div className="mt-1 font-bold">Front camera</div>
                <div className="mt-1 text-xs text-zinc-400">
                  Selfie cam catches the world spinning as it flies.
                </div>
              </button>
            </div>
            <p className="mt-2 text-xs text-zinc-500">
              One camera per throw. Mobile browsers cannot stream front and back at the same time,
              so pick your angle honestly. 📷
            </p>
          </div>

          <div className="mt-5 rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
            <p className="text-sm font-bold text-zinc-200">Beat the blur 💡</p>
            <ul className="mt-2 space-y-1 text-sm text-zinc-400">
              <li>☀️ Film outdoors or under strong light. Bright scene = short exposure = crispy frames.</li>
              <li>⚡ If your camera allows it, we lock a fast shutter automatically.</li>
              <li>🌚 Dim room? Expect ghosting. Lumo Boost rescues brightness in post, not blur.</li>
            </ul>
          </div>

          <button
            onClick={() => void fireUp()}
            className="mt-6 w-full rounded-2xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
          >
            FIRE UP THE LAB 🔬
          </button>

          {(notice ?? rig.error) && (
            <p className="mt-3 rounded-xl border border-amber-400/40 bg-amber-400/10 p-3 text-sm text-amber-200">
              {notice ?? rig.error}
            </p>
          )}

          {demoAvailable && (
            <div className="mt-6 rounded-2xl border border-zinc-800 bg-zinc-900/60 p-4">
              <p className="text-sm font-bold text-zinc-300">Desk pilot mode 🖥️</p>
              <p className="mt-1 text-xs text-zinc-500">
                No throw sensors here. Run a simulated throw through the real engine and get the
                full 3D rebuild with stand-in frames.
              </p>
              <button
                onClick={() => void runDemo()}
                disabled={demoBusy}
                className="mt-3 w-full rounded-xl border border-amber-400/60 bg-zinc-900 px-4 py-3 font-bold text-amber-300 active:scale-95 disabled:opacity-50"
              >
                {demoBusy ? 'Throwing... 🌀' : 'Simulate throw 🎲'}
              </button>
            </div>
          )}
        </section>
      )}

      {phase === 'armed' && (
        <section>
          <div className="relative overflow-hidden rounded-2xl border border-zinc-700 bg-black">
            {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
            <video
              ref={previewRef}
              muted
              playsInline
              autoPlay
              className={`max-h-[55vh] w-full object-contain ${facing === 'user' ? '-scale-x-100' : ''}`}
            />
            <div className="absolute left-3 top-3 flex items-center gap-2 rounded-full bg-zinc-950/80 px-3 py-1 text-xs font-bold">
              <span className="h-2.5 w-2.5 animate-pulse rounded-full bg-red-500" />
              REC
              {rig.capture && <span className="text-zinc-400">{rig.capture.fps} fps</span>}
            </div>
            {rig.capture && (
              <div className="absolute right-3 top-3 rounded-full bg-zinc-950/80 px-3 py-1 text-xs">
                {rig.capture.exposureLocked ? 'Shutter locked ⚡' : 'Auto exposure ☀️'}
              </div>
            )}
            {session.airborne && (
              <div className="absolute inset-x-0 bottom-3 text-center">
                <span className="rounded-full bg-amber-400 px-4 py-1.5 text-sm font-black text-zinc-950">
                  AIRBORNE 🚀 {session.liveFlips > 0 ? `${session.liveFlips} flip${session.liveFlips > 1 ? 's' : ''}!` : ''}
                </span>
              </div>
            )}
          </div>

          <p className="mt-4 text-center text-xl font-black">
            Rolling. Send it! 🤙
          </p>
          <p className="mt-1 text-center text-sm text-zinc-400">
            Throw the phone (or film a buddy throwing theirs). The lab cuts the clip the moment
            the trick lands.
          </p>

          <div className="mt-5 flex gap-3">
            <button
              onClick={() => void cancel()}
              className="flex-1 rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold active:scale-95"
            >
              Bail out ✋
            </button>
            {facing === 'user' && torchState !== 'on' && (
              <button
                onClick={() => void torchFx()}
                className="flex-1 rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold active:scale-95"
              >
                {torchState === 'nope' ? 'No torch API 💡' : 'Torch FX ⚡'}
              </button>
            )}
          </div>
        </section>
      )}

      {phase === 'processing' && (
        <section className="flex flex-col items-center justify-center py-20 text-center">
          <div className="animate-spin text-5xl">🌀</div>
          <p className="mt-4 text-lg font-bold">Cutting the tape...</p>
          <p className="mt-1 text-sm text-zinc-400">
            Trimming the flight, pulling frames, rebuilding the trick in 3D.
          </p>
        </section>
      )}

      {phase === 'review' && take && (
        <section className="space-y-5">
          <ResultCard result={take.result} />

          {take.videoUrl ? (
            <div>
              <h2 className="mb-2 text-lg font-black">Slow-mo replay 🎬</h2>
              <SlowMoPlayer
                src={take.videoUrl}
                launchVideoSec={take.launchVideoSec}
                landVideoSec={take.landVideoSec}
                playheadMsRef={playheadMsRef}
              />
            </div>
          ) : (
            <p className="rounded-2xl border border-zinc-800 bg-zinc-900/60 p-3 text-sm text-zinc-400">
              Desk pilot run: no clip, straight to the 3D rebuild with stand-in frames. 🖥️
            </p>
          )}

          <div>
            <h2 className="mb-2 text-lg font-black">3D rebuild 🌐</h2>
            <TrajectoryViewer
              trajectory={take.result.trajectory}
              frames={viewerFrames}
              playheadMs={take.videoUrl ? () => playheadMsRef.current : undefined}
              className="h-[340px] w-full"
            />
            <p className="mt-1 text-xs text-zinc-500">
              Drag to orbit, pinch to zoom. The little cards are your video frames posed along the
              flight, DA3 style. {take.videoUrl ? 'They follow the replay playhead.' : 'Self-playing.'}
            </p>
          </div>

          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <button
              onClick={newThrow}
              className="rounded-2xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
            >
              RUN IT BACK 🔁
            </button>
            <button
              onClick={() => downloadBundle(take.result, take.frames, take.capture)}
              className="rounded-2xl border border-amber-400/60 bg-zinc-900 px-4 py-4 font-bold text-amber-300 active:scale-95"
            >
              Export DA3 bundle 📦
            </button>
          </div>
          {take.videoBlob && take.capture && (
            <button
              onClick={() => downloadClip(take.videoBlob!, take.capture!.mimeType, take.result)}
              className="w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 text-sm font-semibold text-zinc-300 active:scale-95"
            >
              Save raw clip for the full point-cloud pipeline 💾
            </button>
          )}
          <p className="text-xs text-zinc-500">
            The bundle carries poses, timestamps, an intrinsics guess and up to 12 JPEG frames.
            docs/VIDEO-TO-3D.md explains how to run the real nano-world-model pipeline on the raw
            clip for a full point cloud.
          </p>
        </section>
      )}
    </main>
  );
}
