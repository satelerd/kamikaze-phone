import { useEffect, useMemo, useRef, useState } from 'react';
import { Animated, Easing, Pressable, StyleSheet, Text, View } from 'react-native';

import { PhoneScene3D, type OrbitCamera } from '../components/PhoneScene3D';
import { useOrbitResponder } from '../components/useOrbitResponder';
import { multiplyQuaternion, normalizeQuaternion } from '../motion/replay';
import type { FlightPhase, Quaternion, ReplayFrame } from '../motion/types';
import { fonts } from '../theme';
import { GlassSurface } from './GlassSurface';
import { gameColors, gameRadii } from './theme';

const GAME_CAMERA: OrbitCamera = {
  azimuth: -0.48,
  elevation: 0.22,
  distance: 4.5,
};

const PLAY_POV_CAMERA: OrbitCamera = {
  azimuth: 0,
  elevation: 0,
  distance: 4.5,
};

const phaseLanguage: Record<FlightPhase, { label: string; prompt: string }> = {
  idle: { label: 'READY', prompt: 'Start a session' },
  armed: { label: 'THROW', prompt: 'Watching for motion' },
  airborne: { label: 'AIR', prompt: 'Reading the trick' },
  settling: { label: 'CATCH', prompt: 'Hold it steady' },
  complete: { label: 'LANDED', prompt: 'Attempt captured' },
};

export function GameStage({
  frame,
  height = 440,
  interactive = true,
  phase,
  restOrientation = 'flat',
  sensorHz,
  skinColor,
  zeroable = true,
}: {
  frame: ReplayFrame;
  height?: number;
  interactive?: boolean;
  phase: FlightPhase;
  restOrientation?: 'flat' | 'screen';
  sensorHz: number;
  skinColor: string;
  zeroable?: boolean;
}) {
  const defaultCamera = restOrientation === 'screen' ? PLAY_POV_CAMERA : GAME_CAMERA;
  const pulse = useRef(new Animated.Value(1)).current;
  const spin = useRef(new Animated.Value(0)).current;
  const [camera, setCamera] = useState<OrbitCamera>(defaultCamera);
  const [zeroId, setZeroId] = useState(0);
  const poseBaselineRef = useRef<Quaternion | null>(null);
  const orbitResponder = useOrbitResponder(camera, setCamera, { maximumDistance: 8.4, minimumDistance: 2.8 });
  const displayFrame = useMemo<ReplayFrame>(() => {
    const baseline = poseBaselineRef.current;
    if (!baseline) return frame;
    const inverseBaseline = { w: baseline.w, x: -baseline.x, y: -baseline.y, z: -baseline.z };
    return {
      ...frame,
      quaternion: normalizeQuaternion(multiplyQuaternion(inverseBaseline, frame.quaternion)),
    };
  }, [frame, zeroId]);

  useEffect(() => {
    pulse.stopAnimation();
    spin.stopAnimation();
    pulse.setValue(1);
    spin.setValue(0);

    if (phase === 'armed') {
      Animated.loop(Animated.sequence([
        Animated.timing(pulse, { duration: 620, toValue: 1.06, useNativeDriver: true }),
        Animated.timing(pulse, { duration: 620, toValue: 1, useNativeDriver: true }),
      ])).start();
    }
    if (phase === 'airborne') {
      Animated.loop(Animated.timing(spin, {
        duration: 760,
        easing: Easing.linear,
        toValue: 1,
        useNativeDriver: true,
      })).start();
    }
    if (phase === 'complete') {
      Animated.sequence([
        Animated.spring(pulse, { friction: 4, tension: 150, toValue: 1.12, useNativeDriver: true }),
        Animated.spring(pulse, { friction: 6, tension: 100, toValue: 1, useNativeDriver: true }),
      ]).start();
    }
  }, [phase, pulse, spin]);

  const accent = phase === 'airborne' || phase === 'settling'
    ? gameColors.hazard
    : phase === 'complete'
      ? gameColors.volt
      : gameColors.ion;
  const spinDegrees = spin.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '360deg'] });
  const copy = phaseLanguage[phase];

  return (
    <View style={[styles.stage, { height }]}>
      <View pointerEvents="none" style={styles.stageMaterial}>
        <GlassSurface
          fallbackColor="rgba(112,126,172,0.08)"
          fallbackIntensity={52}
          glassEffectStyle="regular"
          style={styles.stageMaterialFill}
        />
      </View>
      <PhoneScene3D
        camera={camera}
        frame={displayFrame}
        key={skinColor}
        restOrientation={restOrientation}
        shellColor={skinColor}
        tone="blue"
        variant="game"
      />
      {interactive && <View collapsable={false} style={styles.orbitSurface} {...orbitResponder.panHandlers} />}
      <Animated.View
        pointerEvents="none"
        style={[
          styles.haloOuter,
          { borderColor: accent, transform: [{ rotate: spinDegrees }, { scale: pulse }] },
        ]}
      />
      <Animated.View
        pointerEvents="none"
        style={[styles.haloInner, { borderColor: accent, transform: [{ scale: pulse }] }]}
      />
      <View pointerEvents="none" style={styles.crosshairHorizontal} />
      <View pointerEvents="none" style={styles.crosshairVertical} />
      <View pointerEvents="none" style={styles.stageTopline}>
        <View style={[styles.stateDot, { backgroundColor: accent }]} />
        <Text style={[styles.stateLabel, { color: accent }]}>{copy.label}</Text>
        <Text style={styles.hz}>{sensorHz > 0 ? `${Math.round(sensorHz)} HZ` : 'SENSOR IDLE'}</Text>
      </View>
      <View pointerEvents="none" style={styles.stageBottom}>
        <Text style={styles.prompt}>{copy.prompt}</Text>
        <Text style={styles.telemetry}>{frame.accelG.toFixed(2)}G · {Math.round(frame.gyroDps)}°/S</Text>
      </View>
      {interactive && (
        <View style={styles.stageControls}>
          {zeroable && (
            <Pressable
              accessibilityLabel="Zero phone pose"
              onPress={() => {
                poseBaselineRef.current = { ...frame.quaternion };
                setZeroId((value) => value + 1);
              }}
              style={[styles.stageControl, styles.zeroPose]}
            >
              <Text style={styles.stageControlText}>ZERO POSE</Text>
            </Pressable>
          )}
          <Pressable
            accessibilityLabel="Reset 3D camera"
            onPress={() => setCamera({ ...defaultCamera })}
            style={styles.stageControl}
          >
            <Text style={styles.stageControlText}>RESET CAMERA</Text>
          </Pressable>
        </View>
      )}
      {interactive && <Text pointerEvents="none" style={styles.gestureHint}>DRAG · PINCH</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  stage: {
    backgroundColor: 'rgba(8,10,14,0.26)',
    borderRadius: gameRadii.stage,
    overflow: 'hidden',
    position: 'relative',
  },
  orbitSurface: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'transparent',
    zIndex: 4,
  },
  stageMaterial: { ...StyleSheet.absoluteFillObject },
  stageMaterialFill: { flex: 1 },
  haloOuter: {
    borderRadius: 138,
    borderStyle: 'dashed',
    borderWidth: 2,
    height: 276,
    left: '50%',
    marginLeft: -138,
    marginTop: -138,
    position: 'absolute',
    top: '50%',
    width: 276,
  },
  haloInner: {
    borderRadius: 105,
    borderWidth: 1,
    height: 210,
    left: '50%',
    marginLeft: -105,
    marginTop: -105,
    position: 'absolute',
    top: '50%',
    width: 210,
  },
  crosshairHorizontal: {
    backgroundColor: 'rgba(255,255,255,0.14)',
    height: 1,
    left: 24,
    position: 'absolute',
    right: 24,
    top: '50%',
  },
  crosshairVertical: {
    backgroundColor: 'rgba(255,255,255,0.14)',
    bottom: 72,
    left: '50%',
    position: 'absolute',
    top: 58,
    width: 1,
  },
  stageTopline: {
    alignItems: 'center',
    flexDirection: 'row',
    left: 20,
    position: 'absolute',
    right: 20,
    top: 18,
  },
  stateDot: {
    borderRadius: 5,
    height: 9,
    marginRight: 8,
    width: 9,
  },
  stateLabel: {
    fontFamily: fonts.bodyBold,
    fontSize: 12,
    letterSpacing: 1.1,
  },
  hz: {
    color: gameColors.frostMuted,
    fontFamily: fonts.mono,
    fontSize: 9,
    marginLeft: 'auto',
  },
  stageBottom: {
    alignItems: 'flex-end',
    bottom: 18,
    flexDirection: 'row',
    justifyContent: 'space-between',
    left: 20,
    position: 'absolute',
    right: 20,
  },
  prompt: {
    color: gameColors.white,
    fontFamily: fonts.bodyBold,
    fontSize: 15,
  },
  telemetry: {
    color: gameColors.frostMuted,
    fontFamily: fonts.mono,
    fontSize: 8,
  },
  stageControls: {
    flexDirection: 'row',
    gap: 6,
    position: 'absolute',
    right: 18,
    top: 48,
    zIndex: 6,
  },
  stageControl: {
    backgroundColor: 'rgba(10,11,10,0.58)',
    borderColor: 'rgba(255,255,255,0.18)',
    borderRadius: 14,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 10,
    paddingVertical: 7,
  },
  zeroPose: {
    backgroundColor: 'rgba(91,115,255,0.28)',
    borderColor: 'rgba(122,143,255,0.52)',
  },
  stageControlText: {
    color: gameColors.frost,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 0.7,
  },
  gestureHint: {
    color: 'rgba(233,236,248,0.46)',
    fontFamily: fonts.mono,
    fontSize: 6,
    left: 20,
    letterSpacing: 0.7,
    position: 'absolute',
    top: 51,
    zIndex: 6,
  },
});
