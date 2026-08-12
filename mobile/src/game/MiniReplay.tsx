import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { PanResponder, Pressable, StyleSheet, Text, View } from 'react-native';

import { PhoneScene3D, type OrbitCamera } from '../components/PhoneScene3D';
import { useScrollLock } from '../components/ScrollLock';
import { useOrbitResponder } from '../components/useOrbitResponder';
import {
  buildReplayFrames,
  buildTargetFrames,
  normalizeReplayFrames,
  sampleReplayFrame,
} from '../motion/replay';
import type { TrickDefinition } from '../motion/trickCatalog';
import type { DetectedAttempt, ReplayFrame } from '../motion/types';
import { fonts } from '../theme';
import { GlassSurface } from './GlassSurface';
import { gameColors, gameRadii } from './theme';

const REPLAY_CAMERA: OrbitCamera = { azimuth: -0.54, elevation: 0.2, distance: 4.8 };
const PLAYBACK_SPEEDS = [1, 0.5, 0.25] as const;

const clamp = (value: number, minimum = 0, maximum = 1) =>
  Math.min(maximum, Math.max(minimum, value));

function PlaybackIcon({ playing }: { playing: boolean }) {
  if (playing) {
    return (
      <View style={styles.pauseIcon}>
        <View style={styles.pauseBar} />
        <View style={styles.pauseBar} />
      </View>
    );
  }
  return <View style={styles.playIcon} />;
}

export function MiniReplay({
  attempt,
  definition,
  interactive = true,
  shellColor,
}: {
  attempt?: DetectedAttempt | null;
  definition: TrickDefinition;
  interactive?: boolean;
  shellColor: string;
}) {
  const frames = useMemo(() => {
    let sourceFrames: ReplayFrame[];
    if (!attempt) {
      sourceFrames = buildTargetFrames(definition);
    } else {
      const capturedFrames = buildReplayFrames(attempt);
      sourceFrames = capturedFrames.length >= 2
        ? capturedFrames
        : buildTargetFrames({
          ...definition,
          durationMs: Math.max(300, attempt.airtimeMs),
          rotation: {
            x: attempt.rotationDegrees.x,
            y: attempt.rotationDegrees.y,
            z: attempt.rotationDegrees.z,
          },
        });
    }
    return normalizeReplayFrames(sourceFrames);
  }, [attempt, definition]);
  const durationMs = Math.max(1, frames.at(-1)?.timestampMs ?? definition.durationMs);
  const [playheadMs, setPlayheadMs] = useState(0);
  const playheadRef = useRef(0);
  const [playing, setPlaying] = useState(false);
  const [playbackSpeed, setPlaybackSpeed] = useState<(typeof PLAYBACK_SPEEDS)[number]>(0.5);
  const playbackSpeedRef = useRef<(typeof PLAYBACK_SPEEDS)[number]>(playbackSpeed);
  const playbackTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const [camera, setCamera] = useState<OrbitCamera>(REPLAY_CAMERA);
  const timelineWidthRef = useRef(1);
  const timelineOriginRef = useRef(0);
  const setScrollLocked = useScrollLock();
  const orbitResponder = useOrbitResponder(camera, setCamera, { maximumDistance: 8.6, minimumDistance: 2.8 });
  const progress = clamp(playheadMs / durationMs);
  const frame: ReplayFrame = useMemo(
    () => sampleReplayFrame(frames, playheadMs),
    [frames, playheadMs],
  );
  playbackSpeedRef.current = playbackSpeed;

  const clearPlaybackTimer = useCallback(() => {
    if (playbackTimerRef.current === null) return;
    clearInterval(playbackTimerRef.current);
    playbackTimerRef.current = null;
  }, []);

  const stopPlayback = useCallback(() => {
    clearPlaybackTimer();
    setPlaying(false);
  }, [clearPlaybackTimer]);

  const startPlayback = useCallback(() => {
    if (frames.length < 2) return;
    clearPlaybackTimer();
    if (playheadRef.current >= durationMs - 1) {
      playheadRef.current = 0;
      setPlayheadMs(0);
    }

    let previousTickMs = Date.now();
    setPlaying(true);
    playbackTimerRef.current = setInterval(() => {
      const nowMs = Date.now();
      const elapsedMs = Math.min(100, Math.max(0, nowMs - previousTickMs));
      previousTickMs = nowMs;
      const nextMs = Math.min(
        durationMs,
        playheadRef.current + elapsedMs * playbackSpeedRef.current,
      );
      playheadRef.current = nextMs;
      setPlayheadMs(nextMs);

      if (nextMs >= durationMs) {
        clearPlaybackTimer();
        setPlaying(false);
      }
    }, 33);
  }, [clearPlaybackTimer, durationMs, frames.length]);

  useEffect(() => {
    clearPlaybackTimer();
    playheadRef.current = 0;
    setPlayheadMs(0);
    setPlaying(false);
  }, [attempt?.id, clearPlaybackTimer, definition.id]);

  useEffect(() => () => {
    clearPlaybackTimer();
    setScrollLocked(false);
  }, [clearPlaybackTimer, setScrollLocked]);

  const scrubResponder = useMemo(() => PanResponder.create({
    onMoveShouldSetPanResponder: () => true,
    onMoveShouldSetPanResponderCapture: () => true,
    onStartShouldSetPanResponder: () => true,
    onStartShouldSetPanResponderCapture: () => {
      setScrollLocked(true);
      return true;
    },
    onPanResponderGrant: (event) => {
      setScrollLocked(true);
      stopPlayback();
      timelineOriginRef.current = event.nativeEvent.pageX - event.nativeEvent.locationX;
      const nextMs = clamp((event.nativeEvent.pageX - timelineOriginRef.current) / timelineWidthRef.current) * durationMs;
      playheadRef.current = nextMs;
      setPlayheadMs(nextMs);
    },
    onPanResponderMove: (event) => {
      event.stopPropagation?.();
      const nextMs = clamp((event.nativeEvent.pageX - timelineOriginRef.current) / timelineWidthRef.current) * durationMs;
      playheadRef.current = nextMs;
      setPlayheadMs(nextMs);
    },
    onPanResponderRelease: () => setScrollLocked(false),
    onPanResponderTerminate: () => setScrollLocked(false),
    onPanResponderTerminationRequest: () => false,
    onShouldBlockNativeResponder: () => true,
  }), [durationMs, setScrollLocked, stopPlayback]);

  const togglePlayback = () => {
    if (playbackTimerRef.current !== null) stopPlayback();
    else startPlayback();
  };

  return (
    <View style={styles.shell}>
      <View pointerEvents="none" style={styles.material}>
        <GlassSurface
          fallbackColor="rgba(112,126,172,0.08)"
          fallbackIntensity={54}
          glassEffectStyle="regular"
          style={styles.materialFill}
        />
      </View>
      <View style={styles.stage}>
        <PhoneScene3D
          camera={camera}
          frame={frame}
          key={shellColor}
          shellColor={shellColor}
          tone={attempt ? 'blue' : 'coral'}
          variant="game"
        />
        {interactive && (
          <View
            collapsable={false}
            onTouchCancel={() => setScrollLocked(false)}
            onTouchEnd={() => setScrollLocked(false)}
            onTouchMove={(event) => event.stopPropagation()}
            onTouchStart={() => setScrollLocked(true)}
            style={styles.orbitSurface}
            {...orbitResponder.panHandlers}
          />
        )}
        <View pointerEvents="none" style={styles.captionRow}>
          <Text style={styles.caption}>{attempt ? 'YOUR MOTION' : 'CLEAN TARGET'}</Text>
          <Text style={styles.caption}>{Math.round(playheadMs)} MS</Text>
        </View>
        {interactive && (
          <Pressable
            accessibilityLabel="Reset replay camera"
            onPress={() => setCamera({ ...REPLAY_CAMERA })}
            style={styles.resetCamera}
          >
            <Text style={styles.resetCameraText}>RESET CAMERA</Text>
          </Pressable>
        )}
        {interactive && <Text pointerEvents="none" style={styles.gestureHint}>DRAG · PINCH</Text>}
      </View>
      <View style={styles.transport}>
        <Pressable
          accessibilityLabel={playing ? 'Pause replay' : 'Play replay'}
          onPress={togglePlayback}
          style={styles.play}
        >
          <PlaybackIcon playing={playing} />
        </Pressable>
        <View style={styles.timelineColumn}>
          <View
            {...scrubResponder.panHandlers}
            onLayout={(event) => { timelineWidthRef.current = event.nativeEvent.layout.width; }}
            onTouchCancel={() => setScrollLocked(false)}
            onTouchEnd={() => setScrollLocked(false)}
            onTouchMove={(event) => event.stopPropagation()}
            onTouchStart={() => setScrollLocked(true)}
            style={styles.timelineTouch}
          >
            <View style={styles.track}>
              <View style={[styles.fill, { width: `${progress * 100}%` }]} />
              <View style={[styles.thumb, { left: `${progress * 100}%` }]} />
            </View>
          </View>
          <View style={styles.timeRow}>
            <Text style={styles.time}>{(playheadMs / 1000).toFixed(2)}S</Text>
            <Text style={styles.time}>{(durationMs / 1000).toFixed(2)}S</Text>
          </View>
        </View>
        <Pressable
          accessibilityLabel={`Playback speed ${playbackSpeed} times`}
          onPress={() => {
            const index = PLAYBACK_SPEEDS.indexOf(playbackSpeed);
            setPlaybackSpeed(PLAYBACK_SPEEDS[(index + 1) % PLAYBACK_SPEEDS.length]);
          }}
          style={styles.speed}
        >
          <Text style={styles.speedValue}>{playbackSpeed}×</Text>
          <Text style={styles.speedLabel}>SPEED</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  shell: {
    backgroundColor: 'rgba(8,10,14,0.12)',
    borderRadius: gameRadii.card,
    overflow: 'hidden',
    position: 'relative',
  },
  material: { ...StyleSheet.absoluteFillObject },
  materialFill: { flex: 1 },
  stage: {
    height: 310,
    overflow: 'hidden',
    position: 'relative',
  },
  orbitSurface: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'transparent',
    zIndex: 4,
  },
  captionRow: {
    bottom: 14,
    flexDirection: 'row',
    justifyContent: 'space-between',
    left: 16,
    position: 'absolute',
    right: 16,
  },
  caption: {
    color: gameColors.frostMuted,
    fontFamily: fonts.mono,
    fontSize: 8,
    letterSpacing: 0.6,
  },
  resetCamera: {
    backgroundColor: 'rgba(10,11,10,0.62)',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 14,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 10,
    paddingVertical: 7,
    position: 'absolute',
    right: 14,
    top: 14,
    zIndex: 6,
  },
  resetCameraText: {
    color: gameColors.frost,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 0.7,
  },
  gestureHint: {
    color: 'rgba(233,236,248,0.5)',
    fontFamily: fonts.mono,
    fontSize: 6,
    left: 14,
    letterSpacing: 0.7,
    position: 'absolute',
    top: 18,
    zIndex: 6,
  },
  transport: {
    alignItems: 'center',
    borderTopColor: 'rgba(255,255,255,0.12)',
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 12,
    minHeight: 74,
    paddingHorizontal: 14,
  },
  play: {
    alignItems: 'center',
    backgroundColor: gameColors.bone,
    borderRadius: 21,
    height: 42,
    justifyContent: 'center',
    width: 42,
  },
  pauseIcon: { flexDirection: 'row', gap: 3 },
  pauseBar: { backgroundColor: gameColors.pitch, height: 13, width: 3 },
  playIcon: {
    borderBottomWidth: 7,
    borderColor: 'transparent',
    borderLeftColor: gameColors.pitch,
    borderLeftWidth: 11,
    borderTopWidth: 7,
    marginLeft: 3,
  },
  timelineColumn: { flex: 1 },
  timelineTouch: { height: 32, justifyContent: 'center' },
  track: {
    backgroundColor: 'rgba(255,255,255,0.18)',
    borderRadius: 4,
    height: 5,
    overflow: 'visible',
  },
  fill: { backgroundColor: gameColors.hazard, borderRadius: 4, height: 5 },
  thumb: {
    backgroundColor: gameColors.white,
    borderColor: gameColors.hazard,
    borderRadius: 9,
    borderWidth: 3,
    height: 18,
    marginLeft: -9,
    marginTop: -11.5,
    position: 'absolute',
    width: 18,
  },
  timeRow: { flexDirection: 'row', justifyContent: 'space-between' },
  time: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 7 },
  speed: {
    alignItems: 'center',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    height: 44,
    justifyContent: 'center',
    width: 52,
  },
  speedValue: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 12 },
  speedLabel: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 5, marginTop: 1 },
});
