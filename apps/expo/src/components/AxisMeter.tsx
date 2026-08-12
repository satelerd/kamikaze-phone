import { StyleSheet, Text, View } from 'react-native';

import { colors, fonts } from '../theme';

type AxisMeterProps = {
  axis: string;
  value: number;
  maximum?: number;
  accent?: boolean;
};

export function AxisMeter({ axis, value, maximum = 720, accent = false }: AxisMeterProps) {
  const width = Math.min(100, Math.abs(value) / maximum * 100);

  return (
    <View style={styles.row}>
      <Text style={styles.axis}>{axis}</Text>
      <View style={styles.track}>
        <View
          style={[
            styles.fill,
            { width: `${width}%`, backgroundColor: accent ? colors.coral : colors.cobalt },
          ]}
        />
      </View>
      <Text style={styles.value}>{Math.round(value).toString().padStart(4, ' ')}°</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 10,
    marginBottom: 12,
  },
  axis: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 12,
    width: 14,
  },
  track: {
    backgroundColor: '#DAD9D0',
    flex: 1,
    height: 8,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
  },
  value: {
    color: colors.asphalt,
    fontFamily: fonts.mono,
    fontSize: 11,
    textAlign: 'right',
    width: 52,
  },
});
