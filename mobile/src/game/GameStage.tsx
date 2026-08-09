import { useEffect, useRef } from 'react';
import { Animated, Easing, StyleSheet, Text, View } from 'react-native';

import { PhoneScene3D, type OrbitCamera } from '../components/PhoneScene3D';
import type { FlightPhase, ReplayFrame } from '../motion/types';
import { fonts } from '../theme';
import { gameColors, gameRadii } from './theme';

const GAME_CAMERA: OrbitCamera = {
  azimuth: -0.48,
  elevation: 0.22,
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
  phase,
  sensorHz,
  skinColor,
}: {
  frame: ReplayFrame;
  height?: number;
  phase: FlightPhase;
  sensorHz: number;
  skinColor: string;
}) {
  const pulse = useRef(new Animated.Value(1)).current;
  const spin = useRef(new Animated.Value(0)).current;

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
      <PhoneScene3D
        camera={GAME_CAMERA}
        frame={frame}
        shellColor={skinColor}
        tone="blue"
        variant="game"
      />
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
    </View>
  );
}

const styles = StyleSheet.create({
  stage: {
    backgroundColor: gameColors.pitch,
    borderRadius: gameRadii.stage,
    overflow: 'hidden',
    position: 'relative',
  },
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
});
