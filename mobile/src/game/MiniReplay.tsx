import { useEffect, useMemo, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { PhoneScene3D, type OrbitCamera } from '../components/PhoneScene3D';
import { buildReplayFrames, buildTargetFrames } from '../motion/replay';
import type { TrickDefinition } from '../motion/trickCatalog';
import type { DetectedAttempt, ReplayFrame } from '../motion/types';
import { fonts } from '../theme';
import { gameColors, gameRadii } from './theme';

const REPLAY_CAMERA: OrbitCamera = { azimuth: -0.54, elevation: 0.2, distance: 4.8 };

export function MiniReplay({
  attempt,
  definition,
  shellColor,
}: {
  attempt?: DetectedAttempt | null;
  definition: TrickDefinition;
  shellColor: string;
}) {
  const frames = useMemo(
    () => attempt ? buildReplayFrames(attempt) : buildTargetFrames(definition),
    [attempt, definition],
  );
  const [index, setIndex] = useState(0);
  const [playing, setPlaying] = useState(true);
  const frame: ReplayFrame = frames[index] ?? frames[0];

  useEffect(() => {
    setIndex(0);
    setPlaying(true);
  }, [attempt?.id, definition.id]);

  useEffect(() => {
    if (!playing || frames.length < 2) return;
    const timer = setInterval(() => {
      setIndex((current) => {
        if (current >= frames.length - 1) {
          setPlaying(false);
          return current;
        }
        return current + 1;
      });
    }, Math.max(16, definition.durationMs / Math.max(1, frames.length - 1)));
    return () => clearInterval(timer);
  }, [definition.durationMs, frames.length, playing]);

  const progress = frames.length <= 1 ? 0 : index / (frames.length - 1);
  return (
    <View style={styles.shell}>
      <View style={styles.stage}>
        <PhoneScene3D
          camera={REPLAY_CAMERA}
          frame={frame}
          shellColor={shellColor}
          tone={attempt ? 'blue' : 'coral'}
          variant="game"
        />
        <View pointerEvents="none" style={styles.captionRow}>
          <Text style={styles.caption}>{attempt ? 'YOUR MOTION' : 'CLEAN TARGET'}</Text>
          <Text style={styles.caption}>{Math.round(frame.timestampMs)} MS</Text>
        </View>
      </View>
      <View style={styles.transport}>
        <Pressable
          accessibilityLabel={playing ? 'Pause replay' : 'Play replay'}
          onPress={() => {
            if (!playing && index >= frames.length - 1) setIndex(0);
            setPlaying((value) => !value);
          }}
          style={styles.play}
        >
          {playing ? (
            <View style={styles.pauseIcon}>
              <View style={styles.pauseBar} />
              <View style={styles.pauseBar} />
            </View>
          ) : <View style={styles.playIcon} />}
        </Pressable>
        <View style={styles.track}>
          <View style={[styles.fill, { width: `${progress * 100}%` }]} />
        </View>
        <Text style={styles.time}>{(definition.durationMs / 1000).toFixed(2)}S</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  shell: {
    backgroundColor: gameColors.pitchRaised,
    borderRadius: gameRadii.card,
    overflow: 'hidden',
  },
  stage: {
    height: 290,
    overflow: 'hidden',
    position: 'relative',
  },
  captionRow: {
    bottom: 14,
    flexDirection: 'row',
    justifyContent: 'space-between',
    left: 16,
    position: 'absolute',
    right: 16,
  },
  caption: {
    color: gameColors.frostMuted,
    fontFamily: fonts.mono,
    fontSize: 8,
    letterSpacing: 0.6,
  },
  transport: {
    alignItems: 'center',
    borderTopColor: 'rgba(255,255,255,0.12)',
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 12,
    padding: 14,
  },
  play: {
    alignItems: 'center',
    backgroundColor: gameColors.bone,
    borderRadius: 18,
    height: 36,
    justifyContent: 'center',
    width: 36,
  },
  pauseIcon: { flexDirection: 'row', gap: 3 },
  pauseBar: { backgroundColor: gameColors.pitch, height: 12, width: 3 },
  playIcon: {
    borderBottomWidth: 6,
    borderColor: 'transparent',
    borderLeftColor: gameColors.pitch,
    borderLeftWidth: 10,
    borderTopWidth: 6,
    marginLeft: 2,
  },
  track: {
    backgroundColor: 'rgba(255,255,255,0.16)',
    borderRadius: 3,
    flex: 1,
    height: 4,
    overflow: 'hidden',
  },
  fill: { backgroundColor: gameColors.hazard, height: 4 },
  time: {
    color: gameColors.frost,
    fontFamily: fonts.mono,
    fontSize: 9,
  },
});
