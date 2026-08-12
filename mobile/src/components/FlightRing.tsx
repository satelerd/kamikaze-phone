import { useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Animated,
  Easing,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import Svg, { Circle, Line } from 'react-native-svg';

import type { FlightPhase } from '../motion/types';
import { colors, fonts } from '../theme';

type FlightRingProps = {
  phase: FlightPhase;
  accelG: number;
  gyroDps: number;
  rotation: number;
};

const phaseCopy: Record<FlightPhase, { eyebrow: string; word: string }> = {
  idle: { eyebrow: 'SESSION OFF', word: 'READY?' },
  armed: { eyebrow: 'FREEFALL WATCH', word: 'THROW' },
  airborne: { eyebrow: 'PHONE IN AIR', word: 'AIR' },
  settling: { eyebrow: 'VERIFYING CATCH', word: 'HOLD' },
  complete: { eyebrow: 'ATTEMPT LOGGED', word: 'CAUGHT' },
};

export function FlightRing({ phase, accelG, gyroDps, rotation }: FlightRingProps) {
  const spin = useRef(new Animated.Value(0)).current;
  const pulse = useRef(new Animated.Value(1)).current;
  const [reduceMotion, setReduceMotion] = useState(false);

  useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
    const listener = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => listener.remove();
  }, []);

  useEffect(() => {
    spin.stopAnimation();
    pulse.stopAnimation();
    if (reduceMotion) return;

    if (phase === 'airborne') {
      spin.setValue(0);
      Animated.loop(
        Animated.timing(spin, {
          toValue: 1,
          duration: 900,
          easing: Easing.linear,
          useNativeDriver: true,
        }),
      ).start();
    } else if (phase === 'armed') {
      Animated.loop(
        Animated.sequence([
          Animated.timing(pulse, { toValue: 1.035, duration: 650, useNativeDriver: true }),
          Animated.timing(pulse, { toValue: 1, duration: 650, useNativeDriver: true }),
        ]),
      ).start();
    } else {
      spin.setValue(0);
      pulse.setValue(1);
    }
  }, [phase, pulse, reduceMotion, spin]);

  const copy = phaseCopy[phase];
  const phaseColor = phase === 'airborne'
    ? colors.coral
    : phase === 'complete'
      ? colors.cobalt
      : colors.asphalt;
  const spinDegrees = spin.interpolate({ inputRange: [0, 1], outputRange: ['0deg', '360deg'] });

  return (
    <Animated.View style={[styles.shell, { transform: [{ scale: pulse }] }]}>
      <Animated.View style={[styles.svg, { transform: [{ rotate: spinDegrees }] }]}>
        <Svg width="100%" height="100%" viewBox="0 0 280 280">
          <Circle cx="140" cy="140" r="126" stroke={colors.asphalt} strokeWidth="2" fill="none" />
          <Circle
            cx="140"
            cy="140"
            r="113"
            stroke={phaseColor}
            strokeWidth="12"
            strokeDasharray="88 28 14 28"
            strokeLinecap="butt"
            fill="none"
          />
          <Circle cx="140" cy="140" r="93" stroke={colors.concrete} strokeWidth="1" fill="none" />
          <Line x1="17" y1="140" x2="47" y2="140" stroke={colors.asphalt} strokeWidth="3" />
          <Line x1="233" y1="140" x2="263" y2="140" stroke={colors.asphalt} strokeWidth="3" />
          <Line x1="140" y1="17" x2="140" y2="47" stroke={colors.asphalt} strokeWidth="3" />
          <Line x1="140" y1="233" x2="140" y2="263" stroke={colors.asphalt} strokeWidth="3" />
        </Svg>
      </Animated.View>
      <View style={styles.center}>
        <Text style={[styles.eyebrow, { color: phaseColor }]}>{copy.eyebrow}</Text>
        <Text style={styles.word}>{copy.word}</Text>
        <Text style={styles.readout}>{accelG.toFixed(2)}G  /  {Math.round(gyroDps)}°S</Text>
        <Text style={styles.rotation}>{Math.round(rotation)}° PATH</Text>
      </View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  shell: {
    width: 280,
    height: 280,
    alignItems: 'center',
    justifyContent: 'center',
  },
  svg: {
    ...StyleSheet.absoluteFillObject,
  },
  center: {
    alignItems: 'center',
    width: 190,
  },
  eyebrow: {
    fontFamily: fonts.monoBold,
    fontSize: 10,
    letterSpacing: 1.5,
    marginBottom: 8,
  },
  word: {
    color: colors.asphalt,
    fontFamily: fonts.display,
    fontSize: 40,
    letterSpacing: -1.5,
    lineHeight: 43,
  },
  readout: {
    color: colors.asphalt,
    fontFamily: fonts.mono,
    fontSize: 11,
    marginTop: 12,
  },
  rotation: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 9,
    marginTop: 4,
  },
});
