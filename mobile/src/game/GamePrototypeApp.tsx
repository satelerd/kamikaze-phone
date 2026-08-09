import { useEffect, useMemo, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  ActivityIndicator,
  Pressable,
  SafeAreaView,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  useWindowDimensions,
  View,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { useKeepAwake } from 'expo-keep-awake';
import {
  ArchivoBlack_400Regular,
  useFonts as useArchivoFonts,
} from '@expo-google-fonts/archivo-black';
import {
  SpaceGrotesk_400Regular,
  SpaceGrotesk_600SemiBold,
  SpaceGrotesk_700Bold,
  useFonts as useSpaceFonts,
} from '@expo-google-fonts/space-grotesk';
import {
  IBMPlexMono_400Regular,
  IBMPlexMono_600SemiBold,
  useFonts as useMonoFonts,
} from '@expo-google-fonts/ibm-plex-mono';

import { CalibrationHub } from '../components/CalibrationHub';
import { ScrollLockContext } from '../components/ScrollLock';
import { useMotionLab } from '../hooks/useMotionLab';
import { useTrickCatalog, type TrickCatalogController } from '../hooks/useTrickCatalog';
import { findBestTrickMatch, type TrickDefinition, type TrickMatch } from '../motion/trickCatalog';
import type { DetectedAttempt, FlightPhase, ReplayFrame } from '../motion/types';
import { fonts } from '../theme';
import {
  DEFAULT_GAME_PREFERENCES,
  loadGamePreferences,
  saveGamePreferences,
  type GamePreferences,
} from './gameProfile';
import { GameStage } from './GameStage';
import { GlassSurface } from './GlassSurface';
import { KineticBackdrop } from './KineticBackdrop';
import { MiniReplay } from './MiniReplay';
import { gameColors, gameRadii } from './theme';

type GameTab = 'play' | 'practice' | 'locker' | 'profile';
type MotionController = ReturnType<typeof useMotionLab>;
type CaptureMode = 'auto' | 'manual';
type RunComparison = { attempt: DetectedAttempt; label: string; score: number };

const SKINS = [
  { id: 'ion', name: 'ION BLUE', color: gameColors.ion, cost: 0, note: 'Founding deck' },
  { id: 'hazard', name: 'HAZARD', color: gameColors.hazard, cost: 180, note: 'Impact orange' },
  { id: 'volt', name: 'VOLT', color: gameColors.volt, cost: 520, note: 'Night session' },
  { id: 'graphite', name: 'GRAPHITE', color: '#8F928B', cost: 980, note: 'Raw titanium' },
] as const;

const PRACTICE_LEVEL_IDS = [
  'bs-shuvit',
  'fs-shuvit',
  'phone-flip',
  'reverse-phone-flip',
  'front-flip',
  'back-flip',
] as const;

const identityFrame: ReplayFrame = {
  accelG: 1,
  gyroDps: 0,
  progress: 0,
  quaternion: { w: 1, x: 0, y: 0, z: 0 },
  timestampMs: 0,
};

function scoreFor(match: TrickMatch | null | undefined, attempt?: DetectedAttempt | null) {
  return Math.round((match?.overallScore ?? attempt?.confidence ?? 0) * 100);
}

function dateKey(date: Date) {
  const month = `${date.getMonth() + 1}`.padStart(2, '0');
  const day = `${date.getDate()}`.padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

function skinFor(id: string) {
  return SKINS.find((skin) => skin.id === id) ?? SKINS[0];
}

function GameButton({
  label,
  large = false,
  onPress,
  secondary = false,
}: {
  label: string;
  large?: boolean;
  onPress: () => void;
  secondary?: boolean;
}) {
  return (
    <Pressable accessibilityRole="button" onPress={onPress} style={styles.buttonPressable}>
      {({ pressed }) => (
        <GlassSurface
          interactive
          style={[
            styles.gameButton,
            large && styles.gameButtonLarge,
            secondary && styles.gameButtonSecondary,
            pressed && styles.gameButtonPressed,
          ]}
          fallbackColor={secondary ? 'rgba(233,236,248,0.13)' : 'rgba(91,115,255,0.56)'}
          tintColor={secondary ? gameColors.frost : gameColors.ion}
        >
          <Text style={[styles.gameButtonText, secondary && styles.gameButtonTextSecondary]}>{label}</Text>
          <Text style={[styles.gameButtonArrow, secondary && styles.gameButtonTextSecondary]}>→</Text>
        </GlassSurface>
      )}
    </Pressable>
  );
}

function Onboarding({
  motion,
  onComplete,
  skinColor,
}: {
  motion: MotionController;
  onComplete: () => void;
  skinColor: string;
}) {
  const [step, setStep] = useState(0);
  const sensorReady = motion.sensorStatus === 'ready';
  const frame: ReplayFrame = {
    ...identityFrame,
    gyroDps: motion.snapshot.gyroDps,
    accelG: motion.snapshot.accelG,
    quaternion: sensorReady ? motion.liveQuaternion : identityFrame.quaternion,
  };
  const copy = [
    {
      title: 'YOUR PHONE\nIS THE BOARD.',
      body: 'Throw it. Flip it. Catch it. Kamikaze reads the motion and turns every landing into a score.',
    },
    {
      title: 'SOFT LANDINGS.\nHARD TRICKS.',
      body: 'A case and something soft are the smart move. Kamikaze is a game, not a warranty.',
    },
    {
      title: sensorReady ? 'YOU ARE\nCONNECTED.' : 'MAKE IT\nMOVE.',
      body: sensorReady
        ? 'Move the phone. The object below should follow you. Your first guided flip is waiting.'
        : 'Motion access lets the game see rotation, airtime and catches. Nothing leaves the phone unless you share it.',
    },
  ][step];

  return (
    <SafeAreaView style={styles.onboardingSafe}>
      <StatusBar style="light" />
      <KineticBackdrop atmosphere={sensorReady ? 'armed' : 'idle'} />
      <View style={styles.onboardingStage}>
        <GameStage
          frame={frame}
          height={330}
          phase={sensorReady ? 'armed' : 'idle'}
          sensorHz={motion.snapshot.actualHz}
          skinColor={skinColor}
        />
      </View>
      <View style={styles.onboardingCopy}>
        <Text style={styles.onboardingTitle}>{copy.title}</Text>
        <Text style={styles.onboardingBody}>{copy.body}</Text>
      </View>
      <View style={styles.onboardingBottom}>
        <View style={styles.pageDots}>
          {[0, 1, 2].map((index) => (
            <View key={index} style={[styles.pageDot, index === step && styles.pageDotActive]} />
          ))}
        </View>
        {step < 2 ? (
          <GameButton label={step === 0 ? 'SHOW ME HOW' : 'I’LL PLAY SAFE'} onPress={() => setStep(step + 1)} />
        ) : sensorReady ? (
          <GameButton label="ENTER KAMIKAZE" onPress={onComplete} />
        ) : (
          <GameButton label="ENABLE MOTION" onPress={() => { motion.requestPermission(); }} />
        )}
      </View>
    </SafeAreaView>
  );
}

function ResultScreen({
  attempt,
  comparisons,
  definition,
  match,
  onAgain,
  onEnd,
  shellColor,
  streak,
}: {
  attempt: DetectedAttempt;
  comparisons: RunComparison[];
  definition: TrickDefinition;
  match: TrickMatch;
  onAgain: () => void;
  onEnd: () => void;
  shellColor: string;
  streak: number;
}) {
  const score = scoreFor(match, attempt);
  const verdict = score >= 88 ? 'CLEAN' : score >= 68 ? 'LANDED' : 'ROUGH';
  const [replayAttemptId, setReplayAttemptId] = useState(attempt.id);
  const replayAttempt = comparisons.find((item) => item.attempt.id === replayAttemptId)?.attempt ?? attempt;
  return (
    <ScrollView contentContainerStyle={styles.resultContent} showsVerticalScrollIndicator={false}>
      <View style={styles.resultTopline}>
        <Text style={styles.resultVerdict}>{verdict}</Text>
        <Text style={styles.resultStreak}>RUN ×{streak}</Text>
      </View>
      <View style={styles.resultHero}>
        <View style={styles.resultNameWrap}>
          <Text style={styles.resultName}>{definition.name}</Text>
          <Text style={styles.resultMeta}>{(match.motionDurationMs / 1000).toFixed(2)}S · MOTION LOCKED</Text>
        </View>
        <Text style={styles.resultScore}>{score}</Text>
      </View>
      <View style={styles.resultReplay}>
        <MiniReplay attempt={replayAttempt} definition={definition} shellColor={shellColor} />
      </View>
      {comparisons.length > 1 && (
        <View style={styles.comparisonBlock}>
          <Text style={styles.comparisonLabel}>COMPARE RUNS</Text>
          <ScrollView horizontal showsHorizontalScrollIndicator={false}>
            {comparisons.map((item) => {
              const selected = replayAttempt.id === item.attempt.id;
              return (
                <Pressable
                  key={item.attempt.id}
                  onPress={() => setReplayAttemptId(item.attempt.id)}
                  style={[styles.comparisonChip, selected && styles.comparisonChipActive]}
                >
                  <Text style={[styles.comparisonChipLabel, selected && styles.comparisonChipLabelActive]}>{item.label}</Text>
                  <Text style={[styles.comparisonChipScore, selected && styles.comparisonChipLabelActive]}>{item.score}</Text>
                </Pressable>
              );
            })}
          </ScrollView>
        </View>
      )}
      <View style={styles.resultStats}>
        <View>
          <Text style={styles.statValue}>{Math.round(match.axisPurity * 100)}</Text>
          <Text style={styles.statLabel}>AXIS</Text>
        </View>
        <View>
          <Text style={styles.statValue}>{Math.round(attempt.peakRotationDps)}</Text>
          <Text style={styles.statLabel}>PEAK °/S</Text>
        </View>
        <View>
          <Text style={styles.statValue}>+{score}</Text>
          <Text style={styles.statLabel}>POINTS</Text>
        </View>
      </View>
      <GameButton label="THROW AGAIN" onPress={onAgain} />
      <View style={styles.resultSecondaryRow}>
        <Pressable
          onPress={() => {
            Share.share({
              message: `I landed a ${definition.name} — ${score} points in Kamikaze: Phone Flip.`,
            }).catch(() => undefined);
          }}
          style={styles.textAction}
        >
          <Text style={styles.textActionLabel}>SHARE RESULT ↗</Text>
        </Pressable>
        <Pressable onPress={onEnd} style={styles.textAction}>
          <Text style={styles.textActionLabel}>END RUN</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}

function PlayScreen({
  catalog,
  motion,
  shellColor,
}: {
  catalog: TrickCatalogController;
  motion: MotionController;
  shellColor: string;
}) {
  useKeepAwake('kamikaze-active-play-screen');
  const { height: windowHeight } = useWindowDimensions();
  const stageHeight = Math.min(440, Math.max(340, windowHeight - 300));
  const [mode, setMode] = useState<CaptureMode>('auto');
  const [runActive, setRunActive] = useState(false);
  const [showResult, setShowResult] = useState(false);
  const lastPresentedRef = useRef<string | null>(motion.snapshot.lastAttempt?.id ?? null);
  const attempt = motion.snapshot.lastAttempt;
  const match = attempt ? findBestTrickMatch(attempt, catalog.definitions) : null;
  const active = ['armed', 'airborne', 'settling'].includes(motion.snapshot.phase);
  const frame: ReplayFrame = {
    accelG: motion.snapshot.accelG,
    gyroDps: motion.snapshot.gyroDps,
    progress: 0,
    quaternion: motion.liveQuaternion,
    timestampMs: Date.now(),
  };
  const streak = useMemo(() => {
    let count = 0;
    for (const item of motion.attempts) {
      const itemMatch = findBestTrickMatch(item, catalog.definitions);
      if (scoreFor(itemMatch, item) < 55 || itemMatch.definition.family === 'air') break;
      count += 1;
    }
    return count;
  }, [catalog.definitions, motion.attempts]);
  const comparisons = useMemo<RunComparison[]>(() => {
    if (!attempt || !match) return [];
    const matchingHistory = motion.attempts.filter((item) =>
      item.id !== attempt.id &&
      findBestTrickMatch(item, catalog.definitions).definition.id === match.definition.id,
    );
    return [attempt, ...matchingHistory]
      .slice(0, 4)
      .map((item, index) => ({
        attempt: item,
        label: index === 0 ? 'THIS RUN' : `PREV ${index}`,
        score: scoreFor(findBestTrickMatch(item, catalog.definitions), item),
      }));
  }, [attempt, catalog.definitions, match?.definition.id, motion.attempts]);

  useEffect(() => {
    if (
      attempt &&
      motion.snapshot.phase === 'complete' &&
      attempt.id !== lastPresentedRef.current &&
      runActive
    ) {
      lastPresentedRef.current = attempt.id;
      setShowResult(true);
    }
  }, [attempt?.id, motion.snapshot.phase, runActive]);

  const start = async () => {
    setShowResult(false);
    const started = mode === 'manual'
      ? await motion.startManualCapture()
      : await motion.arm();
    setRunActive(started);
  };

  if (showResult && attempt && match) {
    return (
      <ResultScreen
        attempt={attempt}
        comparisons={comparisons}
        definition={match.definition}
        match={match}
        onAgain={() => {
          setShowResult(false);
          if (mode === 'manual') motion.startManualCapture();
          else motion.arm();
        }}
        onEnd={() => {
          motion.disarm();
          setRunActive(false);
          setShowResult(false);
        }}
        shellColor={shellColor}
        streak={Math.max(1, streak)}
      />
    );
  }

  if (motion.manualRecording) {
    return (
      <Pressable
        accessibilityLabel="Stop manual capture"
        onPress={() => { motion.stopManualCapture(); }}
        style={styles.manualFullScreen}
      >
        <View style={styles.playUtilityRow}>
          <View style={styles.liveRunPill}>
            <View style={styles.recordingDot} />
            <Text style={styles.liveRunText}>REC {(motion.manualElapsedMs / 1000).toFixed(2)}S</Text>
          </View>
        </View>
        <GameStage frame={frame} height={stageHeight} interactive={false} phase="airborne" sensorHz={motion.snapshot.actualHz} skinColor={shellColor} />
        <View style={styles.tapAnywhere}>
          <Text style={styles.tapAnywhereTitle}>DO THE TRICK.</Text>
          <Text style={styles.tapAnywhereBody}>Tap anywhere when the phone is back in your hand.</Text>
          <Text style={styles.tapAnywhereAction}>TAP ANYWHERE TO FINISH</Text>
        </View>
      </Pressable>
    );
  }

  return (
    <View style={styles.playScreen}>
      <View style={styles.playUtilityRow}>
        <View style={styles.liveRunPill}>
          <Text style={styles.liveRunText}>{runActive ? `RUN ×${Math.max(1, streak)}` : 'FREE PLAY'}</Text>
        </View>
      </View>
      <GameStage
        frame={frame}
        height={stageHeight}
        phase={active ? motion.snapshot.phase : 'idle'}
        sensorHz={motion.snapshot.actualHz}
        skinColor={shellColor}
      />
      <View style={styles.playInstructionRow}>
        <Text style={styles.playInstruction}>
          {active
            ? motion.snapshot.phase === 'armed'
              ? 'Throw when you are ready.'
              : motion.snapshot.phase === 'airborne'
                ? 'Kamikaze is reading the rotation.'
                : 'Catch and hold for a beat.'
            : 'One tap starts the session. Detection handles the rest.'}
        </Text>
        <View style={styles.modeSwitch}>
          {(['auto', 'manual'] as const).map((item) => (
            <Pressable
              disabled={active}
              key={item}
              onPress={() => setMode(item)}
              style={[styles.modeOption, mode === item && styles.modeOptionActive]}
            >
              <Text style={[styles.modeOptionText, mode === item && styles.modeOptionTextActive]}>{item.toUpperCase()}</Text>
            </Pressable>
          ))}
        </View>
      </View>
      <View style={styles.playActionDock}>
        {active ? (
          <GameButton
            label="SESSION ARMED · CANCEL"
            large
            onPress={() => { motion.disarm(); setRunActive(false); }}
            secondary
          />
        ) : motion.sensorStatus === 'ready' ? (
          <GameButton large label={mode === 'auto' ? 'START SESSION' : 'START MANUAL TRICK'} onPress={start} />
        ) : (
          <GameButton large label="ENABLE MOTION" onPress={() => { motion.requestPermission(); }} />
        )}
      </View>
    </View>
  );
}

function PracticeScreen({
  catalog,
  motion,
  scrollEnabled,
  shellColor,
}: {
  catalog: TrickCatalogController;
  motion: MotionController;
  scrollEnabled: boolean;
  shellColor: string;
}) {
  const levels = PRACTICE_LEVEL_IDS
    .map((id) => catalog.definitions.find((definition) => definition.id === id))
    .filter((definition): definition is TrickDefinition => Boolean(definition));
  const passedCounts = levels.map((level) => motion.attempts.filter((item) => {
    const itemMatch = findBestTrickMatch(item, catalog.definitions);
    return itemMatch.definition.id === level.id && scoreFor(itemMatch, item) >= 55;
  }).length);
  let unlockedLevelCount = 1;
  for (let index = 0; index < levels.length - 1; index += 1) {
    if (passedCounts[index] < 1) break;
    unlockedLevelCount = index + 2;
  }
  const [selectedId, setSelectedId] = useState('bs-shuvit');
  const [attempt, setAttempt] = useState<DetectedAttempt | null>(null);
  const selectedIndex = Math.max(0, levels.findIndex(({ id }) => id === selectedId));
  const definition = levels[selectedIndex] ?? levels[0] ?? catalog.definitions[1];
  const reps = motion.attempts.filter((item) =>
    findBestTrickMatch(item, catalog.definitions).definition.id === definition.id,
  ).length;
  const levelPassed = passedCounts[selectedIndex] > 0;

  if (motion.manualRecording) {
    return (
      <Pressable
        onPress={() => {
          const captured = motion.stopManualCapture();
          if (captured) setAttempt(captured);
        }}
        style={styles.practiceRecording}
      >
        <Text style={styles.eyebrow}>GUIDED REP / {definition.name}</Text>
        <Text style={styles.practiceRecordingTitle}>LAND IT.{`\n`}THEN TAP.</Text>
        <MiniReplay definition={definition} interactive={false} shellColor={shellColor} />
        <Text style={styles.practiceRecordingTime}>{(motion.manualElapsedMs / 1000).toFixed(2)}S RECORDING</Text>
        <Text style={styles.practiceRecordingStop}>THE WHOLE SCREEN STOPS THE CAPTURE</Text>
      </Pressable>
    );
  }

  const match = attempt ? findBestTrickMatch(attempt, catalog.definitions) : null;
  return (
    <ScrollView
      contentContainerStyle={styles.screenScrollContent}
      scrollEnabled={scrollEnabled}
      showsVerticalScrollIndicator={false}
    >
      <Text style={styles.eyebrow}>TRICK PATH / {unlockedLevelCount} OF {levels.length} OPEN</Text>
      <Text style={styles.screenTitle}>EARN THE{`\n`}NEXT MOVE.</Text>
      <Text style={styles.screenIntro}>Land each level once to unlock the next. Three clean reps turns a pass into mastery.</Text>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.levelScroller}>
        {levels.map((item, index) => {
          const unlocked = index < unlockedLevelCount;
          const passed = passedCounts[index] > 0;
          return (
          <Pressable
            disabled={!unlocked}
            key={item.id}
            onPress={() => { setSelectedId(item.id); setAttempt(null); }}
            style={[
              styles.levelCard,
              item.id === definition.id && styles.levelCardActive,
              !unlocked && styles.levelCardLocked,
            ]}
          >
            <View style={styles.levelCardTop}>
              <Text style={[styles.levelNumber, item.id === definition.id && styles.levelCardTextActive]}>
                {String(index + 1).padStart(2, '0')}
              </Text>
              <Text style={[styles.levelState, passed && styles.levelStatePassed]}>
                {!unlocked ? 'LOCKED' : passed ? 'PASSED' : 'OPEN'}
              </Text>
            </View>
            <Text style={[styles.levelName, item.id === definition.id && styles.levelCardTextActive]}>{item.name}</Text>
          </Pressable>
          );
        })}
      </ScrollView>
      <View style={styles.practiceReplay}>
        <MiniReplay attempt={attempt} definition={definition} shellColor={shellColor} />
      </View>
      <View style={styles.practiceProgressRow}>
        <View>
          <Text style={[styles.levelStatus, levelPassed && styles.levelStatusPassed]}>
            LEVEL {String(selectedIndex + 1).padStart(2, '0')} · {levelPassed ? 'PASSED' : 'LAND 55+ TO PASS'}
          </Text>
          <Text style={styles.practiceSelected}>{definition.name}</Text>
          <Text style={styles.practiceDescription}>{definition.description}</Text>
        </View>
        <View style={styles.repBadge}>
          <Text style={styles.repNumber}>{Math.min(reps, 3)}</Text>
          <Text style={styles.repLabel}>/ 3 REPS</Text>
        </View>
      </View>
      {match && attempt && (
        <View style={styles.practiceResultStrip}>
          <Text style={styles.practiceResultName}>LAST REP · {match.definition.name}</Text>
          <Text style={styles.practiceResultScore}>{scoreFor(match, attempt)}</Text>
        </View>
      )}
      <GameButton label={levelPassed ? 'PRACTICE AGAIN' : 'START LEVEL'} onPress={() => { motion.startManualCapture(); }} />
    </ScrollView>
  );
}

function LockerScreen({
  attempts,
  catalog,
  preferences,
  scrollEnabled,
  setPreferences,
}: {
  attempts: DetectedAttempt[];
  catalog: TrickCatalogController;
  preferences: GamePreferences;
  scrollEnabled: boolean;
  setPreferences: (preferences: GamePreferences) => void;
}) {
  const points = attempts.reduce((sum, attempt) =>
    sum + scoreFor(findBestTrickMatch(attempt, catalog.definitions), attempt), 0);
  const selected = skinFor(preferences.selectedSkinId);
  return (
    <ScrollView
      contentContainerStyle={styles.screenScrollContent}
      scrollEnabled={scrollEnabled}
      showsVerticalScrollIndicator={false}
    >
      <Text style={styles.eyebrow}>LOCKER / YOUR PHONE, YOUR DECK</Text>
      <Text style={styles.screenTitle}>BUILD YOUR{`\n`}SIGNATURE.</Text>
      <Text style={styles.screenIntro}>Land tricks, earn points and change the object that represents you in every replay.</Text>
      <View style={styles.lockerStage}>
        <GameStage frame={identityFrame} height={380} phase="idle" sensorHz={0} skinColor={selected.color} />
      </View>
      <View style={styles.pointsRow}>
        <Text style={styles.pointsLabel}>AVAILABLE POINTS</Text>
        <Text style={styles.pointsValue}>{points}</Text>
      </View>
      <View style={styles.skinGrid}>
        {SKINS.map((skin) => {
          const unlocked = points >= skin.cost;
          const active = skin.id === selected.id;
          return (
            <Pressable
              disabled={!unlocked}
              key={skin.id}
              onPress={() => setPreferences({ ...preferences, selectedSkinId: skin.id })}
              style={[styles.skinCard, active && styles.skinCardActive, !unlocked && styles.skinCardLocked]}
            >
              <View style={[styles.skinSwatch, { backgroundColor: skin.color }]} />
              <Text style={styles.skinName}>{skin.name}</Text>
              <Text style={styles.skinNote}>{active ? 'EQUIPPED' : unlocked ? skin.note : `${skin.cost} PTS`}</Text>
            </Pressable>
          );
        })}
      </View>
    </ScrollView>
  );
}

function ActivityGrid({ attempts }: { attempts: DetectedAttempt[] }) {
  const counts = attempts.reduce<Record<string, number>>((result, attempt) => {
    const key = dateKey(new Date(attempt.recordedAtIso));
    result[key] = (result[key] ?? 0) + 1;
    return result;
  }, {});
  const today = new Date();
  const start = new Date(today);
  start.setDate(today.getDate() - 83);
  return (
    <View style={styles.activityGrid}>
      {Array.from({ length: 12 }).map((_, week) => (
        <View key={week} style={styles.activityWeek}>
          {Array.from({ length: 7 }).map((__, day) => {
            const date = new Date(start);
            date.setDate(start.getDate() + week * 7 + day);
            const count = counts[dateKey(date)] ?? 0;
            return (
              <View
                key={day}
                style={[
                  styles.activityCell,
                  count > 0 && styles.activityCellOne,
                  count > 2 && styles.activityCellTwo,
                  count > 5 && styles.activityCellThree,
                ]}
              />
            );
          })}
        </View>
      ))}
    </View>
  );
}

function ProfileScreen({
  catalog,
  motion,
  onOpenDeveloper,
  onReplayOnboarding,
  scrollEnabled,
}: {
  catalog: TrickCatalogController;
  motion: MotionController;
  onOpenDeveloper: () => void;
  onReplayOnboarding: () => void;
  scrollEnabled: boolean;
}) {
  const matches = motion.attempts.map((attempt) => ({
    attempt,
    match: findBestTrickMatch(attempt, catalog.definitions),
  }));
  const landed = matches.filter(({ match }) => match.definition.family !== 'air' && match.overallScore >= 0.55);
  let bestStreak = 0;
  let running = 0;
  [...matches].reverse().forEach(({ match }) => {
    if (match.definition.family !== 'air' && match.overallScore >= 0.55) {
      running += 1;
      bestStreak = Math.max(bestStreak, running);
    } else running = 0;
  });
  const best = landed.reduce<typeof landed[number] | null>((current, item) =>
    !current || item.match.overallScore > current.match.overallScore ? item : current, null);
  const fastest = landed.reduce<typeof landed[number] | null>((current, item) =>
    !current || item.match.motionDurationMs < current.match.motionDurationMs ? item : current, null);
  const longest = landed.reduce<typeof landed[number] | null>((current, item) =>
    !current || item.match.motionDurationMs > current.match.motionDurationMs ? item : current, null);
  const trickCounts = landed.reduce<Record<string, { count: number; name: string }>>((counts, item) => {
    const id = item.match.definition.id;
    const current = counts[id] ?? { count: 0, name: item.match.definition.name };
    counts[id] = { ...current, count: current.count + 1 };
    return counts;
  }, {});
  const mostLanded = Object.values(trickCounts).reduce<{ count: number; name: string } | null>((current, item) =>
    !current || item.count > current.count ? item : current, null);

  return (
    <ScrollView
      contentContainerStyle={styles.screenScrollContent}
      scrollEnabled={scrollEnabled}
      showsVerticalScrollIndicator={false}
    >
      <Text style={styles.eyebrow}>PLAYER / LOCAL PROFILE</Text>
      <View style={styles.profileHero}>
        <View>
          <Text style={styles.profileName}>SAT</Text>
          <Text style={styles.profileLevel}>TEST RIDER · LEVEL {Math.max(1, Math.floor(landed.length / 10) + 1)}</Text>
        </View>
        <View style={styles.profileMark}><Text style={styles.profileMarkText}>K</Text></View>
      </View>
      <View style={styles.bigStats}>
        <View style={styles.bigStat}><Text style={styles.bigStatValue}>{landed.length}</Text><Text style={styles.bigStatLabel}>TOTAL TRICKS</Text></View>
        <View style={styles.bigStat}><Text style={styles.bigStatValue}>{bestStreak}</Text><Text style={styles.bigStatLabel}>BEST RUN</Text></View>
        <View style={styles.bigStat}><Text style={styles.bigStatValue}>{best ? scoreFor(best.match, best.attempt) : '—'}</Text><Text style={styles.bigStatLabel}>HIGH SCORE</Text></View>
      </View>
      <View style={styles.activityCard}>
        <View style={styles.cardHeaderRow}>
          <Text style={styles.cardLabel}>LAST 12 WEEKS</Text>
          <Text style={styles.cardMeta}>{motion.attempts.length} CAPTURES</Text>
        </View>
        <ActivityGrid attempts={motion.attempts} />
        <Text style={styles.activityHint}>More light means more landed tricks that day.</Text>
      </View>
      <Text style={styles.sectionTitle}>PERSONAL BESTS</Text>
      <View style={styles.recordsCard}>
        <View style={styles.recordRow}><Text style={styles.recordLabel}>FASTEST</Text><Text style={styles.recordValue}>{fastest ? `${(fastest.match.motionDurationMs / 1000).toFixed(2)}S` : '—'}</Text></View>
        <View style={styles.recordRow}><Text style={styles.recordLabel}>LONGEST</Text><Text style={styles.recordValue}>{longest ? `${(longest.match.motionDurationMs / 1000).toFixed(2)}S` : '—'}</Text></View>
        <View style={styles.recordRow}><Text style={styles.recordLabel}>MOST LANDED</Text><Text style={styles.recordValue}>{mostLanded?.name ?? '—'}</Text></View>
      </View>
      <View style={styles.cardHeaderRow}>
        <Text style={styles.sectionTitle}>RECENT</Text>
        <Text style={styles.cardMeta}>{motion.historyReady ? `${motion.attempts.length} SAVED` : 'LOADING'}</Text>
      </View>
      {matches.slice(0, 6).map(({ attempt, match }) => (
        <View key={attempt.id} style={styles.recentRow}>
          <View style={styles.recentScore}><Text style={styles.recentScoreText}>{scoreFor(match, attempt)}</Text></View>
          <View style={styles.recentCopy}>
            <Text style={styles.recentName}>{match.definition.name}</Text>
            <Text style={styles.recentMeta}>{(match.motionDurationMs / 1000).toFixed(2)}S · {new Date(attempt.recordedAtIso).toLocaleDateString()}</Text>
          </View>
          <Text style={styles.recentArrow}>→</Text>
        </View>
      ))}
      <View style={styles.settingsCard}>
        <Pressable onPress={onReplayOnboarding} style={styles.settingsRow}>
          <Text style={styles.settingsText}>REPLAY HOW TO PLAY</Text><Text style={styles.settingsArrow}>→</Text>
        </Pressable>
        <Pressable onPress={onOpenDeveloper} style={styles.settingsRow}>
          <Text style={styles.settingsText}>OPEN SENSOR WORKSHOP</Text><Text style={styles.settingsArrow}>→</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}

function BottomNavigation({ tab, setTab }: { tab: GameTab; setTab: (tab: GameTab) => void }) {
  const tabs: { id: GameTab; glyph: string; label: string }[] = [
    { id: 'play', glyph: '●', label: 'PLAY' },
    { id: 'practice', glyph: '↻', label: 'PRACTICE' },
    { id: 'locker', glyph: '◇', label: 'LOCKER' },
    { id: 'profile', glyph: '○', label: 'ME' },
  ];
  return (
    <GlassSurface
      fallbackColor="rgba(28,30,36,0.72)"
      interactive
      style={styles.bottomNav}
      tintColor="rgba(28,30,36,0.42)"
    >
      {tabs.map((item) => (
        <Pressable
          accessibilityRole="tab"
          accessibilityState={{ selected: tab === item.id }}
          key={item.id}
          onPress={() => setTab(item.id)}
          style={[styles.bottomTab, tab === item.id && styles.bottomTabActive]}
        >
          <Text style={[styles.bottomGlyph, tab === item.id && styles.bottomGlyphActive]}>{item.glyph}</Text>
          <Text style={[styles.bottomLabel, tab === item.id && styles.bottomLabelActive]}>{item.label}</Text>
        </Pressable>
      ))}
    </GlassSurface>
  );
}

export default function GamePrototypeApp() {
  const motion = useMotionLab();
  const catalog = useTrickCatalog();
  const [tab, setTab] = useState<GameTab>('play');
  const [scrollLocked, setScrollLocked] = useState(false);
  const [preferences, setPreferencesState] = useState<GamePreferences | null>(null);
  const [showOnboarding, setShowOnboarding] = useState(false);
  const [showDeveloper, setShowDeveloper] = useState(false);
  const [reduceTransparency, setReduceTransparency] = useState(false);
  const [archivoLoaded] = useArchivoFonts({ ArchivoBlack_400Regular });
  const [spaceLoaded] = useSpaceFonts({
    SpaceGrotesk_400Regular,
    SpaceGrotesk_600SemiBold,
    SpaceGrotesk_700Bold,
  });
  const [monoLoaded] = useMonoFonts({ IBMPlexMono_400Regular, IBMPlexMono_600SemiBold });

  useEffect(() => {
    loadGamePreferences().then((stored) => {
      setPreferencesState(stored);
      setShowOnboarding(!stored.onboardingComplete);
    });
    const accessibility = AccessibilityInfo as typeof AccessibilityInfo & {
      isReduceTransparencyEnabled?: () => Promise<boolean>;
    };
    accessibility.isReduceTransparencyEnabled?.().then(setReduceTransparency);
    if (!accessibility.isReduceTransparencyEnabled) return undefined;

    const listener = AccessibilityInfo.addEventListener('reduceTransparencyChanged', setReduceTransparency);
    return () => listener.remove();
  }, []);

  const setPreferences = (next: GamePreferences) => {
    setPreferencesState(next);
    saveGamePreferences(next).catch(() => undefined);
  };

  if (!archivoLoaded || !spaceLoaded || !monoLoaded || !preferences) {
    return (
      <View style={styles.loading}>
        <StatusBar style="light" />
        <ActivityIndicator color={gameColors.volt} />
      </View>
    );
  }

  const completeOnboarding = () => {
    const next = { ...preferences, onboardingComplete: true };
    setPreferences(next);
    setShowOnboarding(false);
    setTab('play');
  };
  const selectedSkin = skinFor(preferences.selectedSkinId);
  const atmosphere = tab === 'play' ? motion.snapshot.phase : tab;

  if (showOnboarding) {
    return <Onboarding motion={motion} onComplete={completeOnboarding} skinColor={selectedSkin.color} />;
  }

  if (showDeveloper) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="light" />
        <ScrollLockContext.Provider value={setScrollLocked}>
          <ScrollView
            contentContainerStyle={styles.developerContent}
            scrollEnabled={!scrollLocked}
            showsVerticalScrollIndicator={false}
          >
            <View style={styles.developerHeader}>
              <View><Text style={styles.eyebrow}>TEST BUILD ONLY</Text><Text style={styles.developerTitle}>SENSOR WORKSHOP</Text></View>
              <Pressable onPress={() => setShowDeveloper(false)} style={styles.developerClose}>
                <Text style={styles.developerCloseText}>DONE</Text>
              </Pressable>
            </View>
            <CalibrationHub catalog={catalog} motion={motion} />
          </ScrollView>
        </ScrollLockContext.Provider>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={[styles.safeArea, reduceTransparency && styles.safeAreaOpaque]}>
      <StatusBar style="light" />
      <ScrollLockContext.Provider value={setScrollLocked}>
        <View style={styles.appShell}>
          {!reduceTransparency && <KineticBackdrop atmosphere={atmosphere} />}
          <View style={styles.screenBody}>
            {tab === 'play' && <PlayScreen catalog={catalog} motion={motion} shellColor={selectedSkin.color} />}
            {tab === 'practice' && (
              <PracticeScreen catalog={catalog} motion={motion} scrollEnabled={!scrollLocked} shellColor={selectedSkin.color} />
            )}
            {tab === 'locker' && (
              <LockerScreen
                attempts={motion.attempts}
                catalog={catalog}
                preferences={preferences}
                scrollEnabled={!scrollLocked}
                setPreferences={setPreferences}
              />
            )}
            {tab === 'profile' && (
              <ProfileScreen
                catalog={catalog}
                motion={motion}
                onOpenDeveloper={() => setShowDeveloper(true)}
                onReplayOnboarding={() => setShowOnboarding(true)}
                scrollEnabled={!scrollLocked}
              />
            )}
          </View>
          <BottomNavigation tab={tab} setTab={setTab} />
        </View>
      </ScrollLockContext.Provider>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  loading: { alignItems: 'center', backgroundColor: gameColors.pitch, flex: 1, justifyContent: 'center' },
  safeArea: { backgroundColor: gameColors.pitch, flex: 1 },
  safeAreaOpaque: { backgroundColor: '#151612' },
  appShell: { flex: 1, position: 'relative' },
  screenBody: { flex: 1, paddingBottom: 92 },
  eyebrow: { color: gameColors.ion, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 1.4 },
  buttonPressable: { borderRadius: gameRadii.control, marginTop: 12 },
  gameButton: {
    alignItems: 'center',
    borderRadius: gameRadii.control,
    flexDirection: 'row',
    justifyContent: 'space-between',
    minHeight: 62,
    paddingHorizontal: 22,
  },
  gameButtonLarge: { minHeight: 82, paddingHorizontal: 28 },
  gameButtonSecondary: {},
  gameButtonPressed: { transform: [{ scale: 0.985 }] },
  gameButtonText: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 15, letterSpacing: 0.3 },
  gameButtonTextSecondary: { color: gameColors.frost },
  gameButtonArrow: { color: gameColors.white, fontFamily: fonts.body, fontSize: 22 },
  onboardingSafe: { backgroundColor: gameColors.pitch, flex: 1 },
  onboardingCopy: { paddingHorizontal: 24, paddingTop: 2 },
  onboardingTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 39, letterSpacing: -1.8, lineHeight: 38 },
  onboardingBody: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 14, lineHeight: 20, marginTop: 13, maxWidth: 340 },
  onboardingStage: { paddingHorizontal: 18, paddingTop: 12 },
  onboardingBottom: { marginTop: 'auto', paddingBottom: 18, paddingHorizontal: 22 },
  pageDots: { flexDirection: 'row', gap: 6, justifyContent: 'center', marginBottom: 2 },
  pageDot: { backgroundColor: '#3D3E38', borderRadius: 3, height: 5, width: 18 },
  pageDotActive: { backgroundColor: gameColors.volt, width: 34 },
  playScreen: { flex: 1, paddingHorizontal: 16, paddingTop: 6 },
  playUtilityRow: { alignItems: 'center', flexDirection: 'row', justifyContent: 'flex-end', minHeight: 38, paddingBottom: 8, paddingHorizontal: 4 },
  liveRunPill: { alignItems: 'center', backgroundColor: 'rgba(35,36,31,0.66)', borderColor: 'rgba(255,255,255,0.12)', borderRadius: 16, borderWidth: StyleSheet.hairlineWidth, flexDirection: 'row', gap: 7, paddingHorizontal: 11, paddingVertical: 8 },
  liveRunText: { color: gameColors.frost, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.7 },
  recordingDot: { backgroundColor: gameColors.hazard, borderRadius: 4, height: 8, width: 8 },
  playInstructionRow: { alignItems: 'center', flexDirection: 'row', gap: 12, justifyContent: 'space-between', marginTop: 14 },
  playInstruction: { color: gameColors.frost, flex: 1, fontFamily: fonts.body, fontSize: 13, lineHeight: 18 },
  playActionDock: { flex: 1, justifyContent: 'flex-end', paddingBottom: 5 },
  modeSwitch: { backgroundColor: '#20211D', borderRadius: 18, flexDirection: 'row', padding: 3 },
  modeOption: { borderRadius: 14, paddingHorizontal: 10, paddingVertical: 7 },
  modeOptionActive: { backgroundColor: gameColors.frost },
  modeOptionText: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 7 },
  modeOptionTextActive: { color: gameColors.pitch },
  manualFullScreen: { flex: 1, paddingHorizontal: 16, paddingTop: 8 },
  tapAnywhere: { alignItems: 'center', flex: 1, justifyContent: 'center', paddingHorizontal: 24 },
  tapAnywhereTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 34, letterSpacing: -1.4 },
  tapAnywhereBody: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 13, lineHeight: 18, marginTop: 8, textAlign: 'center' },
  tapAnywhereAction: { color: gameColors.hazard, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 1.1, marginTop: 18 },
  resultContent: { paddingBottom: 30, paddingHorizontal: 18, paddingTop: 12 },
  resultTopline: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between' },
  resultVerdict: { color: gameColors.volt, fontFamily: fonts.monoBold, fontSize: 10, letterSpacing: 1.4 },
  resultStreak: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 9 },
  resultHero: { alignItems: 'flex-end', flexDirection: 'row', justifyContent: 'space-between', marginBottom: 18, marginTop: 10 },
  resultNameWrap: { flex: 1, paddingBottom: 8 },
  resultName: { color: gameColors.white, fontFamily: fonts.display, fontSize: 34, letterSpacing: -1.5, lineHeight: 35 },
  resultMeta: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 8, letterSpacing: 0.5, marginTop: 7 },
  resultScore: { color: gameColors.volt, fontFamily: fonts.display, fontSize: 76, letterSpacing: -4, lineHeight: 77 },
  resultReplay: { borderColor: 'rgba(215,255,74,0.35)', borderRadius: gameRadii.card, borderWidth: 1 },
  comparisonBlock: { marginTop: 14 },
  comparisonLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.8, marginBottom: 8 },
  comparisonChip: { alignItems: 'center', backgroundColor: 'rgba(255,255,255,0.08)', borderColor: 'transparent', borderRadius: 18, borderWidth: 1, flexDirection: 'row', gap: 8, marginRight: 8, paddingHorizontal: 12, paddingVertical: 9 },
  comparisonChipActive: { backgroundColor: 'rgba(215,255,74,0.12)', borderColor: gameColors.volt },
  comparisonChipLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 7 },
  comparisonChipLabelActive: { color: gameColors.volt },
  comparisonChipScore: { color: gameColors.white, fontFamily: fonts.display, fontSize: 14 },
  resultStats: { flexDirection: 'row', justifyContent: 'space-around', paddingVertical: 18 },
  statValue: { color: gameColors.white, fontFamily: fonts.display, fontSize: 22, textAlign: 'center' },
  statLabel: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 7, marginTop: 3, textAlign: 'center' },
  resultSecondaryRow: { flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 7, paddingTop: 16 },
  textAction: { padding: 8 },
  textActionLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.6 },
  screenScrollContent: { paddingBottom: 28, paddingHorizontal: 18, paddingTop: 20 },
  screenTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 39, letterSpacing: -1.8, lineHeight: 39, marginTop: 9 },
  screenIntro: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 13, lineHeight: 19, marginTop: 11, maxWidth: 340 },
  levelScroller: { marginHorizontal: -18, marginTop: 18, paddingHorizontal: 18 },
  levelCard: { backgroundColor: 'rgba(35,36,31,0.78)', borderColor: 'rgba(255,255,255,0.1)', borderRadius: 20, borderWidth: 1, marginRight: 9, minHeight: 92, padding: 13, width: 142 },
  levelCardActive: { backgroundColor: gameColors.hazard, borderColor: '#FF9A84' },
  levelCardLocked: { opacity: 0.42 },
  levelCardTop: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between' },
  levelNumber: { color: gameColors.frostMuted, fontFamily: fonts.display, fontSize: 17 },
  levelState: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 5, letterSpacing: 0.6 },
  levelStatePassed: { color: gameColors.volt },
  levelName: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 10, lineHeight: 13, marginTop: 14 },
  levelCardTextActive: { color: gameColors.white },
  levelStatus: { color: gameColors.hazard, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.6, marginBottom: 5 },
  levelStatusPassed: { color: gameColors.volt },
  practiceReplay: { marginTop: 16 },
  practiceProgressRow: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between', marginTop: 17 },
  practiceSelected: { color: gameColors.white, fontFamily: fonts.display, fontSize: 22 },
  practiceDescription: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 10, lineHeight: 14, marginTop: 4, maxWidth: 260 },
  repBadge: { alignItems: 'baseline', backgroundColor: gameColors.volt, borderRadius: 18, flexDirection: 'row', paddingHorizontal: 12, paddingVertical: 9 },
  repNumber: { color: gameColors.pitch, fontFamily: fonts.display, fontSize: 18 },
  repLabel: { color: gameColors.pitch, fontFamily: fonts.monoBold, fontSize: 6, marginLeft: 3 },
  practiceResultStrip: { alignItems: 'center', backgroundColor: '#24251F', borderRadius: 18, flexDirection: 'row', justifyContent: 'space-between', marginTop: 14, padding: 13 },
  practiceResultName: { color: gameColors.frost, fontFamily: fonts.monoBold, fontSize: 8 },
  practiceResultScore: { color: gameColors.volt, fontFamily: fonts.display, fontSize: 24 },
  practiceRecording: { flex: 1, justifyContent: 'center', paddingHorizontal: 18, paddingTop: 22 },
  practiceRecordingTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 42, letterSpacing: -1.8, lineHeight: 41, marginBottom: 18, marginTop: 10 },
  practiceRecordingTime: { color: gameColors.hazard, fontFamily: fonts.display, fontSize: 28, marginTop: 18, textAlign: 'center' },
  practiceRecordingStop: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.8, marginTop: 7, textAlign: 'center' },
  lockerStage: { marginTop: 18 },
  pointsRow: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 16 },
  pointsLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.8 },
  pointsValue: { color: gameColors.volt, fontFamily: fonts.display, fontSize: 26 },
  skinGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  skinCard: { backgroundColor: '#20211D', borderColor: 'transparent', borderRadius: gameRadii.card, borderWidth: 1, padding: 14, width: '48%' },
  skinCardActive: { borderColor: gameColors.volt },
  skinCardLocked: { backgroundColor: '#181916' },
  skinSwatch: { borderRadius: 18, height: 68, marginBottom: 12, width: '100%' },
  skinName: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 11 },
  skinNote: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 7, marginTop: 4 },
  profileHero: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between', marginTop: 12 },
  profileName: { color: gameColors.white, fontFamily: fonts.display, fontSize: 47, letterSpacing: -2 },
  profileLevel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.7 },
  profileMark: { alignItems: 'center', backgroundColor: gameColors.hazard, borderRadius: 30, height: 60, justifyContent: 'center', transform: [{ rotate: '7deg' }], width: 60 },
  profileMarkText: { color: gameColors.white, fontFamily: fonts.display, fontSize: 29 },
  bigStats: { flexDirection: 'row', gap: 8, marginTop: 20 },
  bigStat: { backgroundColor: '#20211D', borderRadius: 20, flex: 1, paddingHorizontal: 10, paddingVertical: 15 },
  bigStatValue: { color: gameColors.white, fontFamily: fonts.display, fontSize: 25 },
  bigStatLabel: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 6, marginTop: 4 },
  activityCard: { backgroundColor: gameColors.bone, borderRadius: gameRadii.card, marginTop: 12, padding: 16 },
  cardHeaderRow: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between', marginTop: 20 },
  cardLabel: { color: gameColors.pitch, fontFamily: fonts.bodyBold, fontSize: 11 },
  cardMeta: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 7 },
  activityGrid: { flexDirection: 'row', gap: 4, justifyContent: 'space-between', marginTop: 14 },
  activityWeek: { gap: 4 },
  activityCell: { backgroundColor: '#D7D6CE', borderRadius: 3, height: 14, width: 14 },
  activityCellOne: { backgroundColor: '#AEB9FF' },
  activityCellTwo: { backgroundColor: gameColors.ion },
  activityCellThree: { backgroundColor: gameColors.hazard },
  activityHint: { color: '#77786F', fontFamily: fonts.body, fontSize: 9, marginTop: 12 },
  sectionTitle: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 13, letterSpacing: 0.3, marginTop: 22 },
  recordsCard: { backgroundColor: '#20211D', borderRadius: gameRadii.card, marginTop: 10, paddingHorizontal: 15 },
  recordRow: { alignItems: 'center', borderBottomColor: '#393A34', borderBottomWidth: StyleSheet.hairlineWidth, flexDirection: 'row', justifyContent: 'space-between', minHeight: 54 },
  recordLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 7 },
  recordValue: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 12, maxWidth: 190 },
  recentRow: { alignItems: 'center', borderBottomColor: '#33342F', borderBottomWidth: StyleSheet.hairlineWidth, flexDirection: 'row', minHeight: 66 },
  recentScore: { alignItems: 'center', backgroundColor: gameColors.ion, borderRadius: 16, height: 42, justifyContent: 'center', width: 42 },
  recentScoreText: { color: gameColors.white, fontFamily: fonts.display, fontSize: 16 },
  recentCopy: { flex: 1, marginLeft: 12 },
  recentName: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 12 },
  recentMeta: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 7, marginTop: 3 },
  recentArrow: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 18 },
  settingsCard: { backgroundColor: '#20211D', borderRadius: gameRadii.card, marginTop: 22, overflow: 'hidden' },
  settingsRow: { alignItems: 'center', borderBottomColor: '#393A34', borderBottomWidth: StyleSheet.hairlineWidth, flexDirection: 'row', justifyContent: 'space-between', minHeight: 54, paddingHorizontal: 15 },
  settingsText: { color: gameColors.frost, fontFamily: fonts.bodyBold, fontSize: 10 },
  settingsArrow: { color: gameColors.frostMuted, fontSize: 16 },
  bottomNav: { alignItems: 'center', borderRadius: 34, bottom: 8, flexDirection: 'row', height: 78, left: 12, padding: 6, position: 'absolute', right: 12 },
  bottomTab: { alignItems: 'center', borderRadius: 27, flex: 1, height: 64, justifyContent: 'center' },
  bottomTabActive: { backgroundColor: 'rgba(255,255,255,0.18)' },
  bottomGlyph: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 21, lineHeight: 22 },
  bottomGlyphActive: { color: gameColors.volt },
  bottomLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.5, marginTop: 3 },
  bottomLabelActive: { color: gameColors.white },
  developerContent: { paddingBottom: 40, paddingHorizontal: 20, paddingTop: 10 },
  developerHeader: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between' },
  developerTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 28, marginTop: 5 },
  developerClose: { backgroundColor: gameColors.frost, borderRadius: 18, paddingHorizontal: 14, paddingVertical: 10 },
  developerCloseText: { color: gameColors.pitch, fontFamily: fonts.monoBold, fontSize: 8 },
});
