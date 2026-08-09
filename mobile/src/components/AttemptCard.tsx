import { StyleSheet, Text, View } from 'react-native';

import type { TrickMatch } from '../motion/trickCatalog';
import type { DetectedAttempt } from '../motion/types';
import { colors, fonts } from '../theme';

type AttemptCardProps = {
  attempt: DetectedAttempt;
  match?: TrickMatch | null;
};

export function AttemptCard({ attempt, match }: AttemptCardProps) {
  const score = Math.round((match?.overallScore ?? attempt.confidence) * 100);
  const durationS = (match?.motionDurationMs ?? attempt.airtimeMs) / 1000;
  const verdict = score >= 85 ? 'CLEAN' : score >= 68 ? 'LANDED' : 'REVIEW';
  return (
    <View style={styles.card}>
      <View style={styles.scoreBlock}>
        <Text style={styles.score}>{score}</Text>
        <Text style={styles.scoreLabel}>OVERALL SCORE</Text>
      </View>
      <View style={styles.copy}>
        <View style={styles.verdictTag}>
          <Text style={styles.verdictText}>{verdict}</Text>
        </View>
        <Text style={styles.trick}>{match?.definition.name ?? attempt.trick}</Text>
        <Text style={styles.description}>
          {match?.definition.description ?? 'Recorded sensor attempt.'}
        </Text>
        <Text style={styles.duration}>TRICK DURATION · {durationS.toFixed(2)}S</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    alignItems: 'stretch',
    backgroundColor: colors.paper,
    borderColor: colors.asphalt,
    borderWidth: 1.5,
    flexDirection: 'row',
    marginTop: 24,
    shadowColor: colors.asphalt,
    shadowOffset: { width: 4, height: 4 },
    shadowOpacity: 1,
    shadowRadius: 0,
  },
  scoreBlock: {
    alignItems: 'center',
    backgroundColor: colors.cobalt,
    justifyContent: 'center',
    paddingHorizontal: 15,
    width: 102,
  },
  score: {
    color: colors.white,
    fontFamily: fonts.display,
    fontSize: 48,
    lineHeight: 51,
  },
  scoreLabel: {
    color: '#DDE3FF',
    fontFamily: fonts.monoBold,
    fontSize: 6,
    letterSpacing: 0.7,
    textAlign: 'center',
  },
  copy: {
    flex: 1,
    padding: 15,
  },
  verdictTag: {
    alignSelf: 'flex-start',
    backgroundColor: colors.coral,
    paddingHorizontal: 7,
    paddingVertical: 4,
  },
  verdictText: {
    color: colors.white,
    fontFamily: fonts.monoBold,
    fontSize: 6,
    letterSpacing: 0.9,
  },
  trick: {
    color: colors.asphalt,
    fontFamily: fonts.display,
    fontSize: 21,
    letterSpacing: -0.6,
    marginTop: 7,
  },
  description: {
    color: colors.concrete,
    fontFamily: fonts.body,
    fontSize: 10,
    lineHeight: 14,
    marginTop: 4,
  },
  duration: {
    color: colors.asphalt,
    fontFamily: fonts.monoBold,
    fontSize: 7,
    letterSpacing: 0.45,
    marginTop: 9,
  },
});
