import type { PropsWithChildren } from 'react';
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
  interactive?: boolean;
  style?: StyleProp<ViewStyle>;
  tintColor?: string;
}>;

function canUseLiquidGlass() {
  if (Platform.OS !== 'ios') return false;
  try {
    return isGlassEffectAPIAvailable() && isLiquidGlassAvailable();
  } catch {
    return false;
  }
}

export function GlassSurface({
  children,
  fallbackColor = gameColors.glassFallback,
  interactive = false,
  style,
  tintColor,
}: GlassSurfaceProps) {
  if (canUseLiquidGlass()) {
    return (
      <GlassView
        glassEffectStyle="clear"
        isInteractive={interactive}
        style={style}
        tintColor={tintColor}
      >
        {children}
      </GlassView>
    );
  }

  return <View style={[styles.fallback, { backgroundColor: fallbackColor }, style]}>{children}</View>;
}

const styles = StyleSheet.create({
  fallback: {
    borderColor: 'rgba(255,255,255,0.2)',
    borderWidth: StyleSheet.hairlineWidth,
  },
});
