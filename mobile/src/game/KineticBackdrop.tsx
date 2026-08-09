import { useEffect, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, Easing, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

import type { FlightPhase } from '../motion/types';
import { gameColors } from './theme';

type Atmosphere = FlightPhase | 'practice' | 'locker' | 'profile';

const palettes: Record<Atmosphere, readonly [string, string, string]> = {
  idle: ['#090B12', '#11172B', '#10110F'],
  armed: ['#0A1024', '#29205B', '#10110F'],
  airborne: ['#220B12', '#5C1B24', '#10110F'],
  settling: ['#25120A', '#522415', '#10110F'],
  complete: ['#11190B', '#273D19', '#10110F'],
  practice: ['#0B1021', '#202C54', '#10110F'],
  locker: ['#150E23', '#30204A', '#10110F'],
  profile: ['#0D1415', '#172928', '#10110F'],
};

export function KineticBackdrop({ atmosphere }: { atmosphere: Atmosphere }) {
  const drift = useRef(new Animated.Value(0)).current;
  const [reduceMotion, setReduceMotion] = useState(false);

  useEffect(() => {
    AccessibilityInfo.isReduceMotionEnabled().then(setReduceMotion);
    const listener = AccessibilityInfo.addEventListener('reduceMotionChanged', setReduceMotion);
    return () => listener.remove();
  }, []);

  useEffect(() => {
    if (reduceMotion) {
      drift.stopAnimation();
      drift.setValue(0.5);
      return undefined;
    }
    const loop = Animated.loop(Animated.sequence([
      Animated.timing(drift, {
        duration: atmosphere === 'airborne' ? 1500 : 5200,
        easing: Easing.inOut(Easing.sin),
        toValue: 1,
        useNativeDriver: true,
      }),
      Animated.timing(drift, {
        duration: atmosphere === 'airborne' ? 1500 : 5200,
        easing: Easing.inOut(Easing.sin),
        toValue: 0,
        useNativeDriver: true,
      }),
    ]));
    loop.start();
    return () => loop.stop();
  }, [atmosphere, drift, reduceMotion]);

  const translateA = drift.interpolate({ inputRange: [0, 1], outputRange: [-36, 46] });
  const translateB = drift.interpolate({ inputRange: [0, 1], outputRange: [28, -42] });
  const scale = drift.interpolate({ inputRange: [0, 1], outputRange: [0.92, 1.15] });
  const accent = atmosphere === 'airborne' || atmosphere === 'settling'
    ? gameColors.hazard
    : atmosphere === 'complete'
      ? gameColors.volt
      : gameColors.ion;

  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFillObject}>
      <LinearGradient colors={palettes[atmosphere]} style={StyleSheet.absoluteFillObject} />
      <Animated.View
        style={[
          styles.orb,
          styles.orbA,
          { backgroundColor: accent, transform: [{ translateX: translateA }, { scale }] },
        ]}
      />
      <Animated.View
        style={[
          styles.orb,
          styles.orbB,
          { backgroundColor: palettes[atmosphere][1], transform: [{ translateY: translateB }, { scale }] },
        ]}
      />
      <LinearGradient
        colors={['rgba(16,17,15,0.08)', 'rgba(16,17,15,0.72)', gameColors.pitch]}
        locations={[0, 0.62, 1]}
        style={StyleSheet.absoluteFillObject}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  orb: {
    borderRadius: 999,
    opacity: 0.2,
    position: 'absolute',
  },
  orbA: {
    height: 360,
    right: -170,
    top: -80,
    width: 360,
  },
  orbB: {
    bottom: 40,
    height: 290,
    left: -155,
    width: 290,
  },
});
