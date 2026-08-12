import type { PropsWithChildren } from 'react';
import { BlurView, type BlurTint } from 'expo-blur';
import {
  Platform,
  StyleSheet,
  View,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import {
  GlassView,
  isGlassEffectAPIAvailable,
  isLiquidGlassAvailable,
} from 'expo-glass-effect';

import { gameColors } from './theme';

type GlassSurfaceProps = PropsWithChildren<{
  fallbackColor?: string;
  fallbackIntensity?: number;
  glassEffectStyle?: 'clear' | 'regular';
  interactive?: boolean;
  style?: StyleProp<ViewStyle>;
  tintColor?: string;
}>;

export function canUseLiquidGlass() {
  if (Platform.OS !== 'ios') return false;
  try {
    return isGlassEffectAPIAvailable() && isLiquidGlassAvailable();
  } catch {
    return false;
  }
}

export function GlassSurface({
  children,
  fallbackColor = 'rgba(22,25,34,0.32)',
  fallbackIntensity = 64,
  glassEffectStyle = 'regular',
  interactive = false,
  style,
  tintColor,
}: GlassSurfaceProps) {
  if (canUseLiquidGlass()) {
    return (
      <GlassView
        glassEffectStyle={glassEffectStyle}
        isInteractive={interactive}
        style={style}
        tintColor={tintColor}
      >
        {children}
      </GlassView>
    );
  }

  const blurTint: BlurTint = Platform.OS === 'ios' ? 'systemUltraThinMaterialDark' : 'dark';
  return (
    <BlurView intensity={fallbackIntensity} style={[styles.fallback, style]} tint={blurTint}>
      <View pointerEvents="none" style={[StyleSheet.absoluteFillObject, { backgroundColor: fallbackColor }]} />
      {children}
    </BlurView>
  );
}

const styles = StyleSheet.create({
  fallback: {
    borderColor: 'rgba(255,255,255,0.2)',
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
});
