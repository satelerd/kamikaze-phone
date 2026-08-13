'use client';

// Slow-motion replay of the recorded clip, trimmed around the flight window.
// - playbackRate selector (0.25x / 0.5x / 1x)
// - "Lumo Boost": brightness / contrast / saturation sliders (CSS filter),
//   defaults tuned up because slow-mo + short exposure reads dark
// - scrubber + rAF loop publish the playhead (ms since launch) into a shared
//   ref so the 3D viewer stays in sync
import { useCallback, useEffect, useRef, useState, type MutableRefObject } from 'react';

interface LumoSettings {
  brightness: number;
  contrast: number;
  saturate: number;
}

const LUMO_DEFAULTS: LumoSettings = { brightness: 1.55, contrast: 1.15, saturate: 1.25 };
const RATES = [0.25, 0.5, 1] as const;
const PRE_ROLL_SEC = 0.4;
const POST_ROLL_SEC = 0.6;
const SCRUB_STEPS = 1000;

interface SlowMoPlayerProps {
  src: string;
  /** launch / land moments in video time (seconds) */
  launchVideoSec: number;
  landVideoSec: number;
  /** written every frame with the playhead in ms since launch */
  playheadMsRef: MutableRefObject<number>;
}

export default function SlowMoPlayer({
  src,
  launchVideoSec,
  landVideoSec,
  playheadMsRef,
}: SlowMoPlayerProps) {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const scrubRef = useRef<HTMLInputElement | null>(null);
  const timeLabelRef = useRef<HTMLSpanElement | null>(null);
  const trimRef = useRef({ start: 0, end: 0 });
  const scrubbingRef = useRef(false);
  const [rate, setRate] = useState<number>(0.25);
  const [playing, setPlaying] = useState(false);
  const [lumo, setLumo] = useState<LumoSettings>(LUMO_DEFAULTS);

  // Load the clip, fix Chrome's Infinity-duration webm, seek to the pre-roll.
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    let alive = true;
    const prime = async () => {
      if (!Number.isFinite(v.duration)) {
        v.currentTime = 1e7;
        await new Promise<void>((res) => {
          const done = () => {
            v.removeEventListener('seeked', done);
            res();
          };
          v.addEventListener('seeked', done);
          setTimeout(done, 2500);
        });
      }
      if (!alive) return;
      const dur = Number.isFinite(v.duration) ? v.duration : landVideoSec + POST_ROLL_SEC;
      const start = Number.isFinite(launchVideoSec)
        ? Math.max(0, Math.min(launchVideoSec - PRE_ROLL_SEC, dur))
        : 0;
      const end = Number.isFinite(landVideoSec)
        ? Math.min(dur, landVideoSec + POST_ROLL_SEC)
        : dur;
      trimRef.current = { start, end: Math.max(end, start + 0.2) };
      v.currentTime = start;
      // Muted video may autoplay: roll the slow-mo immediately after the throw.
      v.playbackRate = 0.25;
      void v
        .play()
        .then(() => setPlaying(true))
        .catch(() => setPlaying(false));
    };
    const onMeta = () => void prime();
    if (v.readyState >= 1) void prime();
    else v.addEventListener('loadedmetadata', onMeta);
    return () => {
      alive = false;
      v.removeEventListener('loadedmetadata', onMeta);
    };
  }, [src, launchVideoSec, landVideoSec]);

  // Publish the playhead + drive the trim loop + keep the scrubber honest.
  useEffect(() => {
    let raf = 0;
    const tick = () => {
      raf = requestAnimationFrame(tick);
      const v = videoRef.current;
      if (!v) return;
      const { start, end } = trimRef.current;
      if (!v.paused && end > start && v.currentTime >= end) {
        v.currentTime = start; // loop the flight window
      }
      const launched = Number.isFinite(launchVideoSec) ? launchVideoSec : start;
      playheadMsRef.current = (v.currentTime - launched) * 1000;
      if (!scrubbingRef.current && scrubRef.current && end > start) {
        const f = Math.max(0, Math.min(1, (v.currentTime - start) / (end - start)));
        scrubRef.current.value = String(Math.round(f * SCRUB_STEPS));
      }
      if (timeLabelRef.current) {
        timeLabelRef.current.textContent = `${(playheadMsRef.current / 1000).toFixed(2)}s`;
      }
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [launchVideoSec, playheadMsRef]);

  useEffect(() => {
    const v = videoRef.current;
    if (v) v.playbackRate = rate;
  }, [rate, playing, src]);

  const togglePlay = useCallback(() => {
    const v = videoRef.current;
    if (!v) return;
    if (v.paused) {
      v.playbackRate = rate;
      void v.play();
      setPlaying(true);
    } else {
      v.pause();
      setPlaying(false);
    }
  }, [rate]);

  const onScrub = useCallback((value: string) => {
    const v = videoRef.current;
    if (!v) return;
    const { start, end } = trimRef.current;
    if (end <= start) return;
    v.currentTime = start + (Number(value) / SCRUB_STEPS) * (end - start);
  }, []);

  const filter = `brightness(${lumo.brightness}) contrast(${lumo.contrast}) saturate(${lumo.saturate})`;

  return (
    <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-3">
      <div className="overflow-hidden rounded-xl bg-black">
        {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
        <video
          ref={videoRef}
          src={src}
          muted
          playsInline
          preload="auto"
          onEnded={() => setPlaying(false)}
          style={{ filter }}
          className="max-h-[60vh] w-full object-contain"
        />
      </div>

      <div className="mt-3 flex items-center gap-2">
        <button
          onClick={togglePlay}
          className="rounded-xl bg-amber-400 px-4 py-2 font-bold text-zinc-950 active:scale-95"
        >
          {playing ? 'Pause ⏸' : 'Play ▶️'}
        </button>
        <div className="flex overflow-hidden rounded-xl border border-zinc-700">
          {RATES.map((r) => (
            <button
              key={r}
              onClick={() => setRate(r)}
              className={`px-3 py-2 text-sm font-semibold ${
                rate === r ? 'bg-amber-400 text-zinc-950' : 'bg-zinc-900 text-zinc-300'
              }`}
            >
              {r}x
            </button>
          ))}
        </div>
        <span ref={timeLabelRef} className="ml-auto font-mono text-sm text-zinc-400">
          0.00s
        </span>
      </div>

      <input
        ref={scrubRef}
        type="range"
        min={0}
        max={SCRUB_STEPS}
        defaultValue={0}
        onPointerDown={() => {
          scrubbingRef.current = true;
        }}
        onPointerUp={() => {
          scrubbingRef.current = false;
        }}
        onChange={(e) => onScrub(e.target.value)}
        className="mt-3 w-full accent-amber-400"
        aria-label="Scrub the replay"
      />
      <p className="mt-1 text-xs text-zinc-500">
        Scrub the flight. The 3D rebuild below follows this playhead. 🌀
      </p>

      <div className="mt-4 rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
        <div className="flex items-center justify-between">
          <p className="text-sm font-bold text-zinc-200">Lumo Boost 🔆</p>
          <button
            onClick={() => setLumo(LUMO_DEFAULTS)}
            className="text-xs text-zinc-400 underline underline-offset-2"
          >
            reset
          </button>
        </div>
        <p className="mt-1 text-xs text-zinc-500">
          Slow-mo eats light. Crank it back in post.
        </p>
        {(
          [
            ['brightness', 'Brightness', 0.5, 3],
            ['contrast', 'Contrast', 0.5, 2],
            ['saturate', 'Saturation', 0, 2],
          ] as const
        ).map(([key, label, min, max]) => (
          <label key={key} className="mt-2 block text-xs text-zinc-400">
            <span className="flex justify-between">
              <span>{label}</span>
              <span className="font-mono">{lumo[key].toFixed(2)}</span>
            </span>
            <input
              type="range"
              min={min}
              max={max}
              step={0.05}
              value={lumo[key]}
              onChange={(e) => setLumo((prev) => ({ ...prev, [key]: Number(e.target.value) }))}
              className="mt-1 w-full accent-amber-400"
            />
          </label>
        ))}
      </div>
    </div>
  );
}
