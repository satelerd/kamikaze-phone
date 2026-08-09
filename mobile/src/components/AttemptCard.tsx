import { StyleSheet, Text, View } from 'react-native';

import type { DetectedAttempt } from '../motion/types';
import type { TrickMatch } from '../motion/trickCatalog';
import { colors, fonts } from '../theme';

type AttemptCardProps = {
  attempt: DetectedAttempt;
  match?: TrickMatch | null;
};

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.metric}>
      <Text style={styles.metricValue}>{value}</Text>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
}

export function AttemptCard({ attempt, match }: AttemptCardProps) {
  const isMotionWindow = attempt.captureMode === 'manual' || attempt.triggerMode === 'gyro';
  const quality = Math.round((match?.overallScore ?? attempt.confidence) * 100);
  return (
    <View style={styles.card}>
      <View style={styles.tag}>
        <Text style={styles.tagText}>{quality}% QUALITY</Text>
      </View>
      <Text style={styles.label}>{quality >= 72 ? 'TRICK LANDED' : 'CLOSE / REVIEW'}</Text>
      <Text style={styles.trick}>{match?.definition.name ?? attempt.trick}</Text>
      <View style={styles.rule} />
      <View style={styles.metrics}>
        <Metric label={isMotionWindow ? 'TRICK TIME' : 'AIRTIME'} value={`${Math.round(match?.motionDurationMs ?? attempt.airtimeMs)}MS`} />
        <Metric
          label={isMotionWindow ? 'PEAK GYRO' : 'EST. HEIGHT'}
          value={isMotionWindow ? `${Math.round(attempt.peakRotationDps)}°S` : `${attempt.estimatedHeightM.toFixed(2)}M`}
        />
        <Metric label="ROTATION" value={`${Math.round(attempt.rotationDegrees.total)}°`} />
      </View>
      {match && (
        <View style={styles.qualityStrip}>
          <Metric label="ROTATION MATCH" value={`${Math.round(match.rotationScore * 100)}%`} />
          <Metric label="AXIS PURITY" value={`${Math.round(match.axisPurity * 100)}%`} />
          <Metric label="TIMING" value={`${Math.round(match.timingScore * 100)}%`} />
          <Metric label="CATCH" value={`${Math.round(match.landingScore * 100)}%`} />
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.paper,
    borderColor: colors.asphalt,
    borderWidth: 1.5,
    marginTop: 24,
    padding: 18,
    position: 'relative',
    shadowColor: colors.asphalt,
    shadowOffset: { width: 4, height: 4 },
    shadowOpacity: 1,
    shadowRadius: 0,
  },
  tag: {
    backgroundColor: colors.cobalt,
    paddingHorizontal: 10,
    paddingVertical: 6,
    position: 'absolute',
    right: 14,
    top: -13,
    transform: [{ rotate: '2deg' }],
  },
  tagText: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 9,
    letterSpacing: 1,
  },
  label: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 9,
    letterSpacing: 1.5,
  },
  trick: {
    color: colors.asphalt,
    fontFamily: fonts.display,
    fontSize: 28,
    letterSpacing: -0.8,
    marginTop: 7,
  },
  rule: {
    backgroundColor: colors.asphalt,
    height: 1.5,
    marginVertical: 14,
  },
  metrics: {
    flexDirection: 'row',
    gap: 10,
  },
  qualityStrip: {
    borderTopColor: '#C9C8C0',
    borderTopWidth: 1,
    flexDirection: 'row',
    gap: 7,
    marginTop: 13,
    paddingTop: 12,
  },
  metric: {
    flex: 1,
  },
  metricValue: {
    color: colors.asphalt,
    fontFamily: fonts.bodyBold,
    fontSize: 17,
  },
  metricLabel: {
    color: colors.concrete,
    fontFamily: fonts.mono,
    fontSize: 8,
    letterSpacing: 0.7,
    marginTop: 3,
  },
});
