import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useMotionLab } from '../hooks/useMotionLab';
import type { TrickCatalogController } from '../hooks/useTrickCatalog';
import { colors, fonts } from '../theme';
import { CalibrationBench } from './CalibrationBench';
import { TrickCalibration } from './TrickCalibration';

export function CalibrationHub({
  catalog,
  motion,
}: {
  catalog: TrickCatalogController;
  motion: ReturnType<typeof useMotionLab>;
}) {
  const [mode, setMode] = useState<'axes' | 'tricks'>('axes');
  return (
    <>
      <View style={styles.switcher}>
        {(['axes', 'tricks'] as const).map((item) => (
          <Pressable
            key={item}
            onPress={() => setMode(item)}
            style={[styles.button, mode === item && styles.buttonActive]}
          >
            <Text style={[styles.text, mode === item && styles.textActive]}>
              {item === 'axes' ? 'CALIBRATE MOVEMENT' : 'CALIBRATE TRICKS'}
            </Text>
          </Pressable>
        ))}
      </View>
      {mode === 'axes' ? <CalibrationBench motion={motion} /> : <TrickCalibration catalog={catalog} motion={motion} />}
    </>
  );
}

const styles = StyleSheet.create({
  switcher: { borderColor: colors.asphalt, borderWidth: 1.5, flexDirection: 'row', marginTop: 20 },
  button: { flex: 1, paddingHorizontal: 7, paddingVertical: 12 },
  buttonActive: { backgroundColor: colors.asphalt },
  text: { color: colors.concrete, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.45, textAlign: 'center' },
  textActive: { color: colors.white },
});
