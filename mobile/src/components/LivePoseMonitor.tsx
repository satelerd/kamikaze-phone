import { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import {
  multiplyQuaternion,
  normalizeQuaternion,
  quaternionToEulerDegrees,
} from '../motion/replay';
import type { Quaternion, ReplayFrame } from '../motion/types';
import { colors, fonts } from '../theme';
import { PhoneScene3D } from './PhoneScene3D';

type LivePoseMonitorProps = {
  actualHz: number;
  quaternion: Quaternion;
  ready: boolean;
};

const LIVE_CAMERA = {
  azimuth: -0.36,
  elevation: 0.18,
  distance: 4.6,
};

const inverseQuaternion = (quaternion: Quaternion): Quaternion => ({
  w: quaternion.w,
  x: -quaternion.x,
  y: -quaternion.y,
  z: -quaternion.z,
});

export function LivePoseMonitor({ actualHz, quaternion, ready }: LivePoseMonitorProps) {
  const baselineRef = useRef<Quaternion | null>(null);
  const [calibrationId, setCalibrationId] = useState(0);

  useEffect(() => {
    if (ready && baselineRef.current === null) {
      baselineRef.current = quaternion;
      setCalibrationId((value) => value + 1);
    }
  }, [quaternion, ready]);

  const displayQuaternion = useMemo(() => {
    if (!baselineRef.current) return quaternion;
    return normalizeQuaternion(multiplyQuaternion(
      inverseQuaternion(baselineRef.current),
      quaternion,
    ));
  }, [calibrationId, quaternion]);

  const frame: ReplayFrame = {
    accelG: 1,
    gyroDps: 0,
    progress: 0.5,
    quaternion: displayQuaternion,
    timestampMs: Date.now(),
  };
  const euler = quaternionToEulerDegrees(displayQuaternion);

  const zero = () => {
    baselineRef.current = quaternion;
    setCalibrationId((value) => value + 1);
  };

  return (
    <View style={styles.shell}>
      <View style={styles.header}>
        <View>
          <Text style={styles.kicker}>LIVE POSE / 3D</Text>
          <Text style={styles.title}>MOTION MIRROR.</Text>
        </View>
        <View style={styles.status}>
          <View style={[styles.dot, ready && styles.dotReady]} />
          <Text style={styles.statusText}>{ready ? `${Math.round(actualHz)}HZ` : 'OFF'}</Text>
        </View>
      </View>

      <View style={styles.stage}>
        <PhoneScene3D
          camera={LIVE_CAMERA}
          estimatedHeightM={0.1}
          frame={frame}
          tone="blue"
          variant="pose"
        />
        <View pointerEvents="none" style={styles.stageCopy}>
          <Text style={styles.stageLabel}>ORIENTATION LIVE</Text>
          <Text style={styles.stageLabel}>POSITION LOCKED</Text>
        </View>
        {!ready && (
          <View pointerEvents="none" style={styles.sensorOverlay}>
            <Text style={styles.sensorOverlayText}>ENABLE MOTION SENSOR ABOVE</Text>
          </View>
        )}
      </View>

      <View style={styles.readout}>
        {(['x', 'y', 'z'] as const).map((axis) => (
          <View key={axis} style={styles.axis}>
            <Text style={styles.axisName}>{axis.toUpperCase()}</Text>
            <Text style={styles.axisValue}>{Math.round(euler[axis])}°</Text>
          </View>
        ))}
        <Pressable accessibilityRole="button" onPress={zero} style={styles.zeroButton}>
          <Text style={styles.zeroText}>ZERO ↙</Text>
        </Pressable>
      </View>
      <Text style={styles.footnote}>
        Move and rotate the phone slowly. Zero resets the current pose as the visual origin.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  shell: {
    borderColor: colors.asphalt,
    borderWidth: 1.5,
    marginTop: 28,
  },
  header: {
    alignItems: 'center',
    backgroundColor: colors.paper,
    flexDirection: 'row',
    justifyContent: 'space-between',
    padding: 14,
  },
  kicker: {
    color: colors.cobalt,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 1.15,
  },
  title: {
    color: colors.asphalt,
    fontFamily: fonts.display,
    fontSize: 20,
    letterSpacing: -0.7,
    marginTop: 3,
  },
  status: {
    alignItems: 'center',
    borderColor: colors.asphalt,
    borderWidth: 1,
    flexDirection: 'row',
    gap: 7,
    paddingHorizontal: 9,
    paddingVertical: 7,
  },
  dot: {
    backgroundColor: colors.coral,
    height: 7,
    width: 7,
  },
  dotReady: {
    backgroundColor: colors.cobalt,
  },
  statusText: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 8,
  },
  stage: {
    backgroundColor: colors.asphalt,
    height: 250,
    overflow: 'hidden',
    position: 'relative',
  },
  stageCopy: {
    bottom: 10,
    flexDirection: 'row',
    justifyContent: 'space-between',
    left: 12,
    position: 'absolute',
    right: 12,
  },
  stageLabel: {
    color: '#898A81',
    fontFamily: fonts.mono,
    fontSize: 6,
    letterSpacing: 0.6,
  },
  sensorOverlay: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    backgroundColor: 'rgba(23,24,19,0.78)',
    justifyContent: 'center',
  },
  sensorOverlayText: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 8,
    letterSpacing: 1,
  },
  readout: {
    backgroundColor: '#23241F',
    borderTopColor: '#41423C',
    borderTopWidth: 1,
    flexDirection: 'row',
  },
  axis: {
    borderRightColor: '#41423C',
    borderRightWidth: 1,
    flex: 1,
    paddingHorizontal: 10,
    paddingVertical: 10,
  },
  axisName: {
    color: '#85867D',
    fontFamily: fonts.monoBold,
    fontSize: 7,
  },
  axisValue: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 11,
    marginTop: 2,
  },
  zeroButton: {
    alignItems: 'center',
    backgroundColor: colors.cobalt,
    justifyContent: 'center',
    paddingHorizontal: 13,
  },
  zeroText: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 8,
    letterSpacing: 0.5,
  },
  footnote: {
    backgroundColor: colors.paper,
    color: colors.concrete,
    fontFamily: fonts.body,
    fontSize: 10,
    lineHeight: 15,
    paddingHorizontal: 13,
    paddingVertical: 11,
  },
});
