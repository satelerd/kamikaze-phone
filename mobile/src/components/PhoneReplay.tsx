import { useEffect, useMemo, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  type GestureResponderEvent,
  PanResponder,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';

import { buildReplayFrames, buildTargetFrames } from '../motion/replay';
import { canonicalizeTrickName } from '../motion/tricks';
import type { TrickDefinition } from '../motion/trickCatalog';
import type { DetectedAttempt, ReplayFrame, RotationSummary } from '../motion/types';
import { loadCameraPreset, saveCameraPreset } from '../storage/cameraPreset';
import { colors, fonts } from '../theme';
import { OrbitCamera, PhoneScene3D } from './PhoneScene3D';
import { useScrollLock } from './ScrollLock';

type ReplayMode = 'actual' | 'target';

type PhoneReplayProps = {
  attempt: DetectedAttempt | null;
  targetDefinition?: TrickDefinition;
  targetTrick: string;
};

const DEFAULT_CAMERA: OrbitCamera = {
  azimuth: -0.16,
  elevation: 0.02,
  distance: 7.25,
};
const PLAYBACK_SPEEDS = [1, 0.5, 0.25] as const;
const CAMERA_PRESETS: Record<'SIDE' | 'ISO' | 'POV' | 'TOP', OrbitCamera> = {
  SIDE: DEFAULT_CAMERA,
  ISO: { azimuth: -0.72, elevation: 0.18, distance: 7.6 },
  POV: { azimuth: Math.PI, elevation: 0.04, distance: 7.2 },
  TOP: { azimuth: -0.12, elevation: 1.04, distance: 8.4 },
};

const clamp = (value: number, minimum: number, maximum: number) =>
  Math.min(maximum, Math.max(minimum, value));

type SpatialGesture = {
  camera: OrbitCamera;
  centerX: number;
  centerY: number;
  pinchDistance: number;
  touchCount: number;
};

function readSpatialGesture(
  event: GestureResponderEvent,
  camera: OrbitCamera,
): SpatialGesture | null {
  const touches = event.nativeEvent.touches;
  if (touches.length === 0) return null;
  const first = touches[0];
  const second = touches[1];
  if (!second) {
    return {
      camera,
      centerX: first.pageX,
      centerY: first.pageY,
      pinchDistance: 0,
      touchCount: 1,
    };
  }
  const deltaX = second.pageX - first.pageX;
  const deltaY = second.pageY - first.pageY;
  return {
    camera,
    centerX: (first.pageX + second.pageX) / 2,
    centerY: (first.pageY + second.pageY) / 2,
    pinchDistance: Math.max(1, Math.hypot(deltaX, deltaY)),
    touchCount: touches.length,
  };
}

function getTargetRotation(trick: string, definition?: TrickDefinition): RotationSummary {
  if (definition) {
    const { x, y, z } = definition.rotation;
    return { x, y, z, total: Math.abs(x) + Math.abs(y) + Math.abs(z) };
  }
  const normalized = canonicalizeTrickName(trick).toUpperCase();
  if (normalized.includes('TRE')) return { x: 0, y: 360, z: 360, total: 720 };
  if (normalized.includes('SHUVIT')) return { x: 0, y: 0, z: 360, total: 360 };
  if (normalized.startsWith('PHONE FLIP') || normalized.includes('KAMIKAZE')) {
    return { x: 360, y: 0, z: 0, total: 360 };
  }
  if (normalized.startsWith('FLIP')) return { x: 0, y: 360, z: 0, total: 360 };
  return { x: 360, y: 0, z: 0, total: 360 };
}

function radiansToDegrees(value: number) {
  return Math.round(value * 180 / Math.PI);
}

function cameraCode(camera: OrbitCamera) {
  return `AZ ${radiansToDegrees(camera.azimuth)}° / EL ${radiansToDegrees(camera.elevation)}° / Z ${camera.distance.toFixed(2)}`;
}

function CameraSlider({
  label,
  maximum,
  minimum,
  onChange,
  value,
  valueLabel,
}: {
  label: string;
  maximum: number;
  minimum: number;
  onChange: (value: number) => void;
  value: number;
  valueLabel: string;
}) {
  const widthRef = useRef(1);
  const originRef = useRef(0);
  const onChangeRef = useRef(onChange);
  const setScrollLocked = useScrollLock();
  onChangeRef.current = onChange;
  const update = (pageX: number) => {
    const ratio = clamp((pageX - originRef.current) / widthRef.current, 0, 1);
    onChangeRef.current(minimum + ratio * (maximum - minimum));
  };
  const responder = useMemo(() => PanResponder.create({
    onMoveShouldSetPanResponder: () => true,
    onStartShouldSetPanResponder: () => true,
    onPanResponderGrant: (event) => {
      setScrollLocked(true);
      originRef.current = event.nativeEvent.pageX - event.nativeEvent.locationX;
      update(event.nativeEvent.pageX);
    },
    onPanResponderMove: (event) => update(event.nativeEvent.pageX),
    onPanResponderRelease: () => setScrollLocked(false),
    onPanResponderTerminate: () => setScrollLocked(false),
    onPanResponderTerminationRequest: () => false,
  }), [maximum, minimum, setScrollLocked]);
  const progress = clamp((value - minimum) / (maximum - minimum), 0, 1);
  return (
    <View style={styles.cameraSliderRow}>
      <View style={styles.cameraSliderCopy}>
        <Text style={styles.cameraSliderLabel}>{label}</Text>
        <Text style={styles.cameraSliderValue}>{valueLabel}</Text>
      </View>
      <View
        {...responder.panHandlers}
        onLayout={(event) => { widthRef.current = event.nativeEvent.layout.width; }}
        style={styles.cameraSliderTouch}
      >
        <View style={styles.cameraSliderTrack}>
          <View style={[styles.cameraSliderFill, { width: `${progress * 100}%` }]} />
          <View style={[styles.cameraSliderThumb, { left: `${progress * 100}%` }]} />
        </View>
      </View>
    </View>
  );
}

function AxisReadout({ rotation }: { rotation: RotationSummary }) {
  const values = [
    { axis: 'X', value: rotation.x },
    { axis: 'Y', value: rotation.y },
    { axis: 'Z', value: rotation.z },
  ];
  const dominant = Math.max(...values.map(({ value }) => Math.abs(value)));

  return (
    <View style={styles.axisReadout}>
      {values.map(({ axis, value }) => {
        const isDominant = dominant > 0 && Math.abs(value) === dominant;
        return (
          <View key={axis} style={[styles.axisCell, isDominant && styles.axisCellDominant]}>
            <Text style={[styles.axisLabel, isDominant && styles.axisTextDominant]}>{axis}</Text>
            <Text style={[styles.axisValue, isDominant && styles.axisTextDominant]}>
              {value >= 0 ? '+' : '−'}{Math.abs(Math.round(value))}°
            </Text>
          </View>
        );
      })}
    </View>
  );
}

function PlaybackIcon({ playing }: { playing: boolean }) {
  if (playing) {
    return (
      <View style={styles.pauseIcon}>
        <View style={styles.pauseBar} />
        <View style={styles.pauseBar} />
      </View>
    );
  }
  return <View style={styles.playTriangle} />;
}

export function PhoneReplay({ attempt, targetDefinition, targetTrick }: PhoneReplayProps) {
  const [mode, setMode] = useState<ReplayMode>(attempt ? 'actual' : 'target');
  const [progress, setProgress] = useState(0);
  const [playing, setPlaying] = useState(true);
  const [camera, setCamera] = useState<OrbitCamera>(DEFAULT_CAMERA);
  const [reduceMotion, setReduceMotion] = useState(false);
  const [playbackSpeed, setPlaybackSpeed] = useState<(typeof PLAYBACK_SPEEDS)[number]>(1);
  const [showCameraTools, setShowCameraTools] = useState(false);
  const [savedCamera, setSavedCamera] = useState<OrbitCamera | null>(null);
  const [cameraSaved, setCameraSaved] = useState(false);
  const timelineWidthRef = useRef(1);
  const timelineOriginXRef = useRef(0);
  const cameraRef = useRef(DEFAULT_CAMERA);
  const spatialGestureRef = useRef<SpatialGesture | null>(null);
  const setScrollLocked = useScrollLock();

  cameraRef.current = camera;

  const actualFrames = useMemo(() => attempt ? buildReplayFrames(attempt) : [], [attempt]);
  const targetFrames = useMemo(
    () => buildTargetFrames(targetDefinition ?? targetTrick),
    [targetDefinition, targetTrick],
  );
  const displayedMode = mode === 'actual' && actualFrames.length > 0 ? 'actual' : 'target';
  const frames = displayedMode === 'actual' ? actualFrames : targetFrames;
  const frameIndex = Math.min(frames.length - 1, Math.round(progress * (frames.length - 1)));
  const frame: ReplayFrame = frames[frameIndex] ?? targetFrames[0];
  const durationMs = displayedMode === 'actual'
    ? Math.max(attempt?.airtimeMs ?? 0, frames.at(-1)?.timestampMs ?? 0, 1)
    : Math.max(frames.at(-1)?.timestampMs ?? 900, 1);
  const rotation = displayedMode === 'actual' && attempt
    ? attempt.rotationDegrees
    : getTargetRotation(targetTrick, targetDefinition);
  const estimatedHeightM = displayedMode === 'actual' && attempt
    ? attempt.estimatedHeightM > 0.02 ? attempt.estimatedHeightM : 0.46
    : targetDefinition?.verticalTravelM ?? 0.58;
  const isMotionWindow = attempt?.captureMode === 'manual' || attempt?.triggerMode === 'gyro';

  useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
    const listener = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => listener.remove();
  }, []);

  useEffect(() => {
    loadCameraPreset().then((stored) => {
      if (!stored) return;
      setSavedCamera(stored);
      setCamera(stored);
    });
  }, []);

  useEffect(() => () => setScrollLocked(false), [setScrollLocked]);

  useEffect(() => {
    setProgress(0);
    setPlaying(!reduceMotion);
  }, [displayedMode, frames, reduceMotion]);

  useEffect(() => {
    if (!attempt && mode === 'actual') setMode('target');
  }, [attempt, mode]);

  useEffect(() => {
    if (attempt) setMode('actual');
  }, [attempt?.id]);

  useEffect(() => {
    if (!playing || reduceMotion) return;
    let previous = Date.now();
    const timer = setInterval(() => {
      const now = Date.now();
      const delta = now - previous;
      previous = now;
      setProgress((value) => {
        const next = value + delta * playbackSpeed / Math.max(durationMs * 1.35, 900);
        if (next >= 1) {
          setPlaying(false);
          return 1;
        }
        return next;
      });
    }, 33);
    return () => clearInterval(timer);
  }, [durationMs, playbackSpeed, playing, reduceMotion]);

  const orbitResponder = useMemo(() => {
    const beginGesture = (event: GestureResponderEvent) => {
      setScrollLocked(true);
      spatialGestureRef.current = readSpatialGesture(event, cameraRef.current);
    };
    const endGesture = () => {
      spatialGestureRef.current = null;
      setScrollLocked(false);
    };

    return PanResponder.create({
      onMoveShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponderCapture: () => true,
      onPanResponderGrant: beginGesture,
      onPanResponderMove: (event) => {
        const touches = event.nativeEvent.touches;
        if (touches.length === 0) return;

        if (!spatialGestureRef.current || spatialGestureRef.current.touchCount !== touches.length) {
          beginGesture(event);
          return;
        }

        const start = spatialGestureRef.current;
        const current = readSpatialGesture(event, start.camera);
        if (!current) return;

        const centerDeltaX = current.centerX - start.centerX;
        const centerDeltaY = current.centerY - start.centerY;
        const nextCamera: OrbitCamera = {
          azimuth: start.camera.azimuth - centerDeltaX * 0.01,
          elevation: clamp(start.camera.elevation + centerDeltaY * 0.0065, -0.18, 1.12),
          distance: start.camera.distance,
        };

        if (current.touchCount >= 2 && start.pinchDistance > 0) {
          nextCamera.distance = clamp(
            start.camera.distance * start.pinchDistance / current.pinchDistance,
            3.6,
            11.5,
          );
        }

        cameraRef.current = nextCamera;
        setCamera(nextCamera);
      },
      onPanResponderRelease: endGesture,
      onPanResponderTerminate: endGesture,
      onPanResponderTerminationRequest: () => false,
      onShouldBlockNativeResponder: () => true,
      onStartShouldSetPanResponder: () => true,
    });
  }, [setScrollLocked]);

  const scrubResponder = useMemo(() => PanResponder.create({
    onMoveShouldSetPanResponder: () => true,
    onStartShouldSetPanResponder: () => true,
    onPanResponderGrant: (event) => {
      setScrollLocked(true);
      setPlaying(false);
      timelineOriginXRef.current = event.nativeEvent.pageX - event.nativeEvent.locationX;
      setProgress(clamp((event.nativeEvent.pageX - timelineOriginXRef.current) / timelineWidthRef.current, 0, 1));
    },
    onPanResponderMove: (event) => {
      setProgress(clamp((event.nativeEvent.pageX - timelineOriginXRef.current) / timelineWidthRef.current, 0, 1));
    },
    onPanResponderRelease: () => setScrollLocked(false),
    onPanResponderTerminate: () => setScrollLocked(false),
    onPanResponderTerminationRequest: () => false,
  }), [setScrollLocked]);

  const replay = () => {
    setProgress(0);
    setPlaying(!reduceMotion);
  };

  const togglePlayback = () => {
    if (playing) {
      setPlaying(false);
      return;
    }
    if (progress >= 1) setProgress(0);
    setPlaying(!reduceMotion);
  };

  const switchMode = (nextMode: ReplayMode) => {
    if (nextMode === 'actual' && !attempt) return;
    setMode(nextMode);
    setProgress(0);
    setPlaying(!reduceMotion);
  };

  return (
    <View style={styles.shell}>
      <View style={styles.stageHeader}>
        <View>
          <Text style={styles.stageLabel}>{isMotionWindow ? 'MOTION WINDOW / 3D' : 'FLIGHT ANALYSIS / 3D'}</Text>
          <Text style={styles.stageTitle} numberOfLines={1}>
            {displayedMode === 'actual'
              ? targetDefinition?.name ?? canonicalizeTrickName(attempt?.trick ?? 'AIR')
              : targetDefinition?.name ?? canonicalizeTrickName(targetTrick)}
          </Text>
        </View>
        <View style={styles.livePill}>
          <View style={[styles.liveDot, displayedMode === 'target' && styles.liveDotTarget]} />
          <Text style={styles.liveText}>{displayedMode === 'actual' ? 'SENSOR' : 'TARGET'}</Text>
        </View>
      </View>

      <View style={styles.stage}>
        <PhoneScene3D
          camera={camera}
          estimatedHeightM={estimatedHeightM}
          frame={frame}
          tone={displayedMode === 'actual' ? 'blue' : 'coral'}
          variant="flight"
        />
        <View style={styles.orbitSurface} {...orbitResponder.panHandlers} />
        <View pointerEvents="none" style={styles.stageLegend}>
          <Text style={styles.stageHint}>1 FINGER: ORBIT · PINCH: ZOOM</Text>
          <Text style={styles.stageHint}>{`${estimatedHeightM.toFixed(2)}M VERTICAL EST. · ROTATION MEASURED`}</Text>
        </View>
        <View style={styles.cameraControls}>
          <Pressable
            accessibilityLabel="Zoom in"
            onPress={() => setCamera((value) => ({ ...value, distance: clamp(value.distance - 0.7, 3.6, 11.5) }))}
            style={styles.cameraButton}
          >
            <Text style={styles.cameraButtonText}>＋</Text>
          </Pressable>
          <Pressable
            accessibilityLabel="Zoom out"
            onPress={() => setCamera((value) => ({ ...value, distance: clamp(value.distance + 0.7, 3.6, 11.5) }))}
            style={styles.cameraButton}
          >
            <Text style={styles.cameraButtonText}>−</Text>
          </Pressable>
          <Pressable
            accessibilityLabel="Open camera toolkit"
            onPress={() => setShowCameraTools((value) => !value)}
            style={[styles.cameraButton, styles.cameraPresetButton]}
          >
            <Text style={styles.cameraPresetText}>CAM</Text>
          </Pressable>
        </View>
      </View>

      {showCameraTools && (
        <View style={styles.cameraToolkit}>
          <View style={styles.cameraToolkitHeader}>
            <View>
              <Text style={styles.cameraToolkitKicker}>CAMERA RIG / LIVE</Text>
              <Text style={styles.cameraToolkitCode}>{cameraCode(camera)}</Text>
            </View>
            <Pressable onPress={() => setShowCameraTools(false)} style={styles.cameraClose}>
              <Text style={styles.cameraCloseText}>CLOSE</Text>
            </Pressable>
          </View>

          <View style={styles.cameraPresets}>
            {Object.entries(CAMERA_PRESETS).map(([name, preset]) => (
              <Pressable
                key={name}
                onPress={() => { setCamera(preset); setCameraSaved(false); }}
                style={styles.cameraPresetChip}
              >
                <Text style={styles.cameraPresetChipText}>{name}</Text>
              </Pressable>
            ))}
            {savedCamera && (
              <Pressable onPress={() => setCamera(savedCamera)} style={[styles.cameraPresetChip, styles.cameraPresetSaved]}>
                <Text style={styles.cameraPresetChipText}>SAVED</Text>
              </Pressable>
            )}
          </View>

          <CameraSlider
            label="AZIMUTH / ORBIT"
            maximum={Math.PI}
            minimum={-Math.PI}
            onChange={(azimuth) => { setCamera((value) => ({ ...value, azimuth })); setCameraSaved(false); }}
            value={camera.azimuth}
            valueLabel={`${radiansToDegrees(camera.azimuth)}°`}
          />
          <CameraSlider
            label="ELEVATION / TILT"
            maximum={1.12}
            minimum={-0.18}
            onChange={(elevation) => { setCamera((value) => ({ ...value, elevation })); setCameraSaved(false); }}
            value={camera.elevation}
            valueLabel={`${radiansToDegrees(camera.elevation)}°`}
          />
          <CameraSlider
            label="DISTANCE / ZOOM"
            maximum={11.5}
            minimum={3.6}
            onChange={(distance) => { setCamera((value) => ({ ...value, distance })); setCameraSaved(false); }}
            value={camera.distance}
            valueLabel={camera.distance.toFixed(2)}
          />

          <View style={styles.cameraSaveRow}>
            <Text style={styles.cameraHelp}>ADJUST HERE OR DIRECTLY ON THE 3D. SEND THIS CAMERA CODE TO REPRODUCE THE VIEW.</Text>
            <Pressable
              onPress={() => {
                const next = { ...camera };
                setSavedCamera(next);
                setCameraSaved(true);
                saveCameraPreset(next).catch(() => undefined);
              }}
              style={[styles.cameraSaveButton, cameraSaved && styles.cameraSaveButtonDone]}
            >
              <Text style={[styles.cameraSaveText, cameraSaved && styles.cameraSaveTextDone]}>
                {cameraSaved ? 'VIEW SAVED' : 'SAVE VIEW'}
              </Text>
            </Pressable>
          </View>
        </View>
      )}

      <View style={styles.transport}>
        <Pressable
          accessibilityLabel={playing ? 'Pause replay' : 'Play replay'}
          accessibilityRole="button"
          onPress={togglePlayback}
          style={styles.playButton}
        >
          <PlaybackIcon playing={playing} />
        </Pressable>
        <View style={styles.timelineColumn}>
          <View style={styles.timeRow}>
            <Text style={styles.timeText}>{Math.round(progress * durationMs)}MS</Text>
            <Text style={styles.timeText}>{Math.round(durationMs)}MS</Text>
          </View>
          <View
            {...scrubResponder.panHandlers}
            onLayout={(event) => { timelineWidthRef.current = event.nativeEvent.layout.width; }}
            style={styles.timelineTouch}
          >
            <View style={styles.timelineTrack}>
              <View style={[styles.timelineFill, { width: `${progress * 100}%` }]} />
              <View style={[styles.timelineThumb, { left: `${progress * 100}%` }]} />
            </View>
          </View>
        </View>
        <Pressable
          accessibilityLabel={`Playback speed ${playbackSpeed} times`}
          accessibilityRole="button"
          onPress={() => {
            const index = PLAYBACK_SPEEDS.indexOf(playbackSpeed);
            setPlaybackSpeed(PLAYBACK_SPEEDS[(index + 1) % PLAYBACK_SPEEDS.length]);
          }}
          style={styles.speedButton}
        >
          <Text style={styles.speedValue}>{playbackSpeed}×</Text>
          <Text style={styles.speedLabel}>SPEED</Text>
        </Pressable>
      </View>

      <AxisReadout rotation={rotation} />

      <View style={styles.replayControls}>
        <View style={styles.modeSwitch}>
          <Pressable
            accessibilityRole="button"
            disabled={!attempt}
            onPress={() => switchMode('actual')}
            style={[styles.modeButton, displayedMode === 'actual' && styles.modeButtonActual, !attempt && styles.modeButtonDisabled]}
          >
            <Text style={[styles.modeText, displayedMode === 'actual' && styles.modeTextActive]}>ACTUAL</Text>
          </Pressable>
          <Pressable
            accessibilityRole="button"
            onPress={() => switchMode('target')}
            style={[styles.modeButton, displayedMode === 'target' && styles.modeButtonTarget]}
          >
            <Text style={[styles.modeText, displayedMode === 'target' && styles.modeTextActive]}>TARGET</Text>
          </Pressable>
        </View>
        <Pressable accessibilityRole="button" onPress={replay} style={styles.replayButton}>
          <Text style={styles.replayText}>REPLAY ↻</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  shell: {
    backgroundColor: colors.asphalt,
    borderColor: colors.asphalt,
    borderWidth: 1.5,
    marginTop: 20,
  },
  stageHeader: {
    alignItems: 'center',
    borderBottomColor: '#404139',
    borderBottomWidth: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    minHeight: 67,
    paddingHorizontal: 16,
    paddingVertical: 11,
  },
  stageLabel: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 1.2,
  },
  stageTitle: {
    color: colors.white,
    fontFamily: fonts.display,
    fontSize: 18,
    marginTop: 2,
    maxWidth: 230,
  },
  livePill: {
    alignItems: 'center',
    borderColor: '#51534B',
    borderWidth: 1,
    flexDirection: 'row',
    gap: 7,
    paddingHorizontal: 9,
    paddingVertical: 7,
  },
  liveDot: {
    backgroundColor: colors.cobalt,
    borderRadius: 4,
    height: 7,
    width: 7,
  },
  liveDotTarget: {
    backgroundColor: colors.coral,
  },
  liveText: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 0.7,
  },
  stage: {
    height: 410,
    overflow: 'hidden',
    position: 'relative',
  },
  orbitSurface: {
    ...StyleSheet.absoluteFillObject,
  },
  stageLegend: {
    bottom: 11,
    flexDirection: 'row',
    justifyContent: 'space-between',
    left: 13,
    position: 'absolute',
    right: 13,
  },
  stageHint: {
    color: '#8A8B82',
    fontFamily: fonts.mono,
    fontSize: 6,
    letterSpacing: 0.45,
  },
  cameraControls: {
    gap: 6,
    position: 'absolute',
    right: 10,
    top: 10,
  },
  cameraButton: {
    alignItems: 'center',
    backgroundColor: 'rgba(23,24,19,0.84)',
    borderColor: '#5A5B53',
    borderWidth: 1,
    height: 34,
    justifyContent: 'center',
    width: 34,
  },
  cameraButtonText: {
    color: colors.white,
    fontFamily: fonts.bodyMedium,
    fontSize: 17,
    lineHeight: 19,
  },
  cameraPresetButton: {
    width: 48,
  },
  cameraPresetText: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 0.7,
  },
  cameraToolkit: {
    backgroundColor: '#20211D',
    borderTopColor: '#4A4C44',
    borderTopWidth: 1,
    padding: 14,
  },
  cameraToolkitHeader: {
    alignItems: 'flex-start',
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  cameraToolkitKicker: {
    color: colors.cobalt,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 1,
  },
  cameraToolkitCode: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 11,
    marginTop: 5,
  },
  cameraClose: {
    borderColor: '#5A5B53',
    borderWidth: 1,
    paddingHorizontal: 9,
    paddingVertical: 7,
  },
  cameraCloseText: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 6,
    letterSpacing: 0.7,
  },
  cameraPresets: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 6,
    marginTop: 13,
  },
  cameraPresetChip: {
    borderColor: '#5A5B53',
    borderWidth: 1,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  cameraPresetSaved: {
    backgroundColor: colors.cobalt,
    borderColor: colors.cobalt,
  },
  cameraPresetChipText: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 0.6,
  },
  cameraSliderRow: {
    borderTopColor: '#41423C',
    borderTopWidth: 1,
    marginTop: 12,
    paddingTop: 10,
  },
  cameraSliderCopy: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  cameraSliderLabel: {
    color: '#9A9B91',
    fontFamily: fonts.monoBold,
    fontSize: 6,
    letterSpacing: 0.7,
  },
  cameraSliderValue: {
    color: colors.coral,
    fontFamily: fonts.monoBold,
    fontSize: 8,
  },
  cameraSliderTouch: {
    height: 34,
    justifyContent: 'center',
  },
  cameraSliderTrack: {
    backgroundColor: '#494A44',
    height: 3,
    position: 'relative',
  },
  cameraSliderFill: {
    backgroundColor: colors.cobalt,
    height: 3,
  },
  cameraSliderThumb: {
    backgroundColor: colors.white,
    borderColor: colors.cobalt,
    borderWidth: 3,
    height: 18,
    marginLeft: -9,
    marginTop: -10.5,
    position: 'absolute',
    top: 0,
    width: 18,
  },
  cameraSaveRow: {
    alignItems: 'flex-end',
    borderTopColor: '#41423C',
    borderTopWidth: 1,
    flexDirection: 'row',
    gap: 12,
    marginTop: 10,
    paddingTop: 11,
  },
  cameraHelp: {
    color: '#85867D',
    flex: 1,
    fontFamily: fonts.mono,
    fontSize: 6,
    lineHeight: 10,
  },
  cameraSaveButton: {
    backgroundColor: colors.white,
    paddingHorizontal: 12,
    paddingVertical: 11,
  },
  cameraSaveButtonDone: {
    backgroundColor: colors.cobalt,
  },
  cameraSaveText: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 0.6,
  },
  cameraSaveTextDone: {
    color: colors.white,
  },
  transport: {
    alignItems: 'center',
    borderTopColor: '#404139',
    borderTopWidth: 1,
    flexDirection: 'row',
    gap: 8,
    paddingHorizontal: 13,
    paddingVertical: 12,
  },
  playButton: {
    alignItems: 'center',
    backgroundColor: colors.white,
    height: 48,
    justifyContent: 'center',
    width: 48,
  },
  pauseIcon: {
    flexDirection: 'row',
    gap: 5,
  },
  pauseBar: {
    backgroundColor: colors.asphalt,
    height: 18,
    width: 5,
  },
  playTriangle: {
    borderBottomColor: 'transparent',
    borderBottomWidth: 10,
    borderLeftColor: colors.asphalt,
    borderLeftWidth: 16,
    borderTopColor: 'transparent',
    borderTopWidth: 10,
    marginLeft: 3,
  },
  speedButton: {
    alignItems: 'center',
    borderColor: '#55564E',
    borderWidth: 1,
    height: 48,
    justifyContent: 'center',
    width: 52,
  },
  speedValue: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 11,
  },
  speedLabel: {
    color: '#85867D',
    fontFamily: fonts.monoBold,
    fontSize: 5,
    letterSpacing: 0.8,
    marginTop: 2,
  },
  timelineColumn: {
    flex: 1,
  },
  timeRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  timeText: {
    color: '#96978D',
    fontFamily: fonts.mono,
    fontSize: 7,
  },
  timelineTouch: {
    height: 44,
    justifyContent: 'center',
  },
  timelineTrack: {
    backgroundColor: '#484A43',
    height: 5,
    position: 'relative',
  },
  timelineFill: {
    backgroundColor: colors.white,
    height: 5,
  },
  timelineThumb: {
    backgroundColor: colors.coral,
    borderColor: colors.white,
    borderWidth: 2,
    height: 22,
    marginLeft: -11,
    marginTop: -13.5,
    position: 'absolute',
    top: 0,
    width: 22,
  },
  axisReadout: {
    borderTopColor: '#404139',
    borderTopWidth: 1,
    flexDirection: 'row',
  },
  axisCell: {
    borderRightColor: '#404139',
    borderRightWidth: 1,
    flex: 1,
    gap: 3,
    paddingHorizontal: 13,
    paddingVertical: 11,
  },
  axisCellDominant: {
    backgroundColor: '#292B25',
  },
  axisLabel: {
    color: '#83847B',
    fontFamily: fonts.monoBold,
    fontSize: 7,
  },
  axisValue: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 13,
  },
  axisTextDominant: {
    color: colors.coral,
  },
  replayControls: {
    alignItems: 'center',
    backgroundColor: '#23241F',
    borderTopColor: '#404139',
    borderTopWidth: 1,
    flexDirection: 'row',
    justifyContent: 'space-between',
    padding: 10,
  },
  modeSwitch: {
    flexDirection: 'row',
  },
  modeButton: {
    borderColor: '#55564E',
    borderWidth: 1,
    paddingHorizontal: 12,
    paddingVertical: 8,
  },
  modeButtonActual: {
    backgroundColor: colors.cobalt,
    borderColor: colors.cobalt,
  },
  modeButtonTarget: {
    backgroundColor: colors.coral,
    borderColor: colors.coral,
  },
  modeButtonDisabled: {
    opacity: 0.35,
  },
  modeText: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 8,
  },
  modeTextActive: {
    color: colors.white,
  },
  replayButton: {
    padding: 8,
  },
  replayText: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 9,
    letterSpacing: 0.8,
  },
});
