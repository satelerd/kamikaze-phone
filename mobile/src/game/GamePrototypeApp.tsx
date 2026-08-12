import { useEffect, useMemo, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  ActivityIndicator,
  Alert,
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
import Svg, { Circle, Path, Rect } from 'react-native-svg';
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
import {
  findBestTrickMatch,
  scoreAttemptAgainstTrick,
  type TrickDefinition,
  type TrickMatch,
} from '../motion/trickCatalog';
import type { DetectedAttempt, FlightPhase, ReplayFrame } from '../motion/types';
import { fonts } from '../theme';
import {
  loadGamePreferences,
  saveGamePreferences,
  type GamePreferences,
} from './gameProfile';
import { GameStage } from './GameStage';
import { canUseLiquidGlass, GlassSurface } from './GlassSurface';
import { KineticBackdrop } from './KineticBackdrop';
import { MiniReplay } from './MiniReplay';
import { QuickCalibration } from './QuickCalibration';
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
  mode = 'run',
  onAgain,
  onBack,
  onEnd,
  scrollEnabled,
  shellColor,
  streak,
}: {
  attempt: DetectedAttempt;
  comparisons: RunComparison[];
  definition: TrickDefinition;
  match: TrickMatch;
  mode?: 'recent' | 'run';
  onAgain?: () => void;
  onBack?: () => void;
  onEnd?: () => void;
  scrollEnabled: boolean;
  shellColor: string;
  streak?: number;
}) {
  const [replayAttemptId, setReplayAttemptId] = useState(attempt.id);
  const replayAttempt = comparisons.find((item) => item.attempt.id === replayAttemptId)?.attempt ?? attempt;
  const replayMatch = replayAttempt.id === attempt.id
    ? match
    : scoreAttemptAgainstTrick(replayAttempt, definition);
  const score = scoreFor(replayMatch, replayAttempt);
  const verdict = score >= 88 ? 'CLEAN' : score >= 68 ? 'LANDED' : 'ROUGH';
  const signedDegrees = (value: number) => `${value >= 0 ? '+' : '−'}${Math.round(Math.abs(value))}°`;
  return (
    <ScrollView
      contentContainerStyle={styles.resultContent}
      scrollEnabled={scrollEnabled}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.resultTopline}>
        <Text style={styles.resultVerdict}>{mode === 'recent' ? 'SAVED ATTEMPT' : verdict}</Text>
        <Text style={styles.resultStreak}>
          {mode === 'recent'
            ? new Date(replayAttempt.recordedAtIso).toLocaleDateString()
            : `RUN ×${streak ?? 1}`}
        </Text>
      </View>
      <View style={styles.resultHero}>
        <View style={styles.resultNameWrap}>
          <Text style={styles.resultName}>{definition.name}</Text>
          <Text style={styles.resultMeta}>{(replayMatch.motionDurationMs / 1000).toFixed(2)}S · MOTION LOCKED</Text>
        </View>
        <Text style={styles.resultScore}>{score}</Text>
      </View>
      <View style={styles.resultReplay}>
        <MiniReplay attempt={replayAttempt} definition={definition} shellColor={shellColor} />
      </View>
      <GameButton
        label={mode === 'recent' ? 'BACK TO RECENT' : 'THROW AGAIN'}
        onPress={mode === 'recent' ? onBack! : onAgain!}
      />
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
          <Text style={styles.statValue}>{Math.round(replayMatch.axisPurity * 100)}</Text>
          <Text style={styles.statLabel}>AXIS</Text>
        </View>
        <View>
          <Text style={styles.statValue}>{Math.round(replayAttempt.peakRotationDps)}</Text>
          <Text style={styles.statLabel}>PEAK °/S</Text>
        </View>
        <View>
          <Text style={styles.statValue}>+{score}</Text>
          <Text style={styles.statLabel}>POINTS</Text>
        </View>
      </View>
      <GlassSurface
        fallbackColor="rgba(235,238,248,0.07)"
        fallbackIntensity={48}
        style={styles.telemetryCard}
        tintColor="rgba(235,238,248,0.06)"
      >
        <View style={styles.telemetryHeader}>
          <Text style={styles.telemetryTitle}>MOTION BREAKDOWN</Text>
          <Text style={styles.telemetryMeta}>{replayAttempt.sampleCount} SAMPLES</Text>
        </View>
        <View style={styles.telemetryAxes}>
          {(['x', 'y', 'z'] as const).map((axis) => (
            <View key={axis} style={styles.telemetryAxis}>
              <Text style={styles.telemetryAxisLabel}>{axis.toUpperCase()}</Text>
              <Text style={styles.telemetryAxisValue}>{signedDegrees(replayAttempt.rotationDegrees[axis])}</Text>
            </View>
          ))}
        </View>
        <View style={styles.telemetryRows}>
          <View style={styles.telemetryRow}>
            <Text style={styles.telemetryRowLabel}>AIRTIME</Text>
            <Text style={styles.telemetryRowValue}>{(replayAttempt.airtimeMs / 1000).toFixed(2)} S</Text>
            <Text style={styles.telemetryRowLabel}>HEIGHT</Text>
            <Text style={styles.telemetryRowValue}>{Math.round(replayAttempt.estimatedHeightM * 100)} CM</Text>
          </View>
          <View style={styles.telemetryRow}>
            <Text style={styles.telemetryRowLabel}>CATCH</Text>
            <Text style={styles.telemetryRowValue}>{replayAttempt.peakCatchG.toFixed(2)} G</Text>
            <Text style={styles.telemetryRowLabel}>LANDING</Text>
            <Text style={styles.telemetryRowValue}>{Math.round(replayMatch.landingScore * 100)}%</Text>
          </View>
          <View style={styles.telemetryRow}>
            <Text style={styles.telemetryRowLabel}>ROTATION</Text>
            <Text style={styles.telemetryRowValue}>{Math.round(replayMatch.rotationScore * 100)}%</Text>
            <Text style={styles.telemetryRowLabel}>TIMING</Text>
            <Text style={styles.telemetryRowValue}>{Math.round(replayMatch.timingScore * 100)}%</Text>
          </View>
        </View>
      </GlassSurface>
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
        <Pressable
          onPress={() => Alert.alert(
            'VIDEO EXPORT',
            'The replay data is ready, but Expo Go cannot encode this 3D scene to a video file. This will activate in the standalone app build.',
          )}
          style={styles.textAction}
        >
          <Text style={styles.textActionLabel}>EXPORT VIDEO</Text>
        </Pressable>
        {mode === 'run' && (
          <Pressable onPress={onEnd} style={styles.textAction}>
            <Text style={styles.textActionLabel}>END RUN</Text>
          </Pressable>
        )}
      </View>
    </ScrollView>
  );
}

function PlayScreen({
  catalog,
  motion,
  onOpenFullCalibration,
  scrollEnabled,
  shellColor,
}: {
  catalog: TrickCatalogController;
  motion: MotionController;
  onOpenFullCalibration: () => void;
  scrollEnabled: boolean;
  shellColor: string;
}) {
  useKeepAwake('kamikaze-active-play-screen');
  const { height: windowHeight } = useWindowDimensions();
  const stageHeight = Math.min(440, Math.max(340, windowHeight - 300));
  const [mode, setMode] = useState<CaptureMode>('auto');
  const [runActive, setRunActive] = useState(false);
  const [showResult, setShowResult] = useState(false);
  const [showQuickCalibration, setShowQuickCalibration] = useState(false);
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

  if (showQuickCalibration) {
    return (
      <QuickCalibration
        motion={motion}
        onClose={() => setShowQuickCalibration(false)}
        onOpenFull={() => {
          setShowQuickCalibration(false);
          onOpenFullCalibration();
        }}
        shellColor={shellColor}
      />
    );
  }

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
        scrollEnabled={scrollEnabled}
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
        <GameStage frame={frame} height={stageHeight} interactive={false} phase="airborne" restOrientation="screen" sensorHz={motion.snapshot.actualHz} skinColor={shellColor} />
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
        {runActive ? (
          <View style={styles.liveRunPill}><Text style={styles.liveRunText}>RUN ×{Math.max(1, streak)}</Text></View>
        ) : (
          <Pressable onPress={() => setShowQuickCalibration(true)}>
            <GlassSurface fallbackColor="rgba(126,140,188,0.12)" fallbackIntensity={62} interactive style={styles.quickCalPill}>
              <View style={styles.quickCalDot} />
              <Text style={styles.quickCalText}>QUICK CALIBRATE</Text>
              <Text style={styles.quickCalArrow}>→</Text>
            </GlassSurface>
          </Pressable>
        )}
      </View>
      <GameStage
        frame={frame}
        height={stageHeight}
        phase={active ? motion.snapshot.phase : 'idle'}
        restOrientation="screen"
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
  const [captureMode, setCaptureMode] = useState<CaptureMode>('auto');
  const [levelActive, setLevelActive] = useState(false);
  const lastPracticeAttemptRef = useRef<string | null>(motion.snapshot.lastAttempt?.id ?? null);
  const selectedIndex = Math.max(0, levels.findIndex(({ id }) => id === selectedId));
  const definition = levels[selectedIndex] ?? levels[0] ?? catalog.definitions[1];
  const reps = motion.attempts.filter((item) =>
    findBestTrickMatch(item, catalog.definitions).definition.id === definition.id,
  ).length;
  const levelPassed = passedCounts[selectedIndex] > 0;
  const liveFrame: ReplayFrame = {
    accelG: motion.snapshot.accelG,
    gyroDps: motion.snapshot.gyroDps,
    progress: 0,
    quaternion: motion.liveQuaternion,
    timestampMs: Date.now(),
  };

  useEffect(() => {
    const captured = motion.snapshot.lastAttempt;
    if (
      levelActive &&
      captured &&
      motion.snapshot.phase === 'complete' &&
      captured.id !== lastPracticeAttemptRef.current
    ) {
      lastPracticeAttemptRef.current = captured.id;
      setAttempt(captured);
      setLevelActive(false);
    }
  }, [levelActive, motion.snapshot.lastAttempt?.id, motion.snapshot.phase]);

  const startLevel = async () => {
    setAttempt(null);
    lastPracticeAttemptRef.current = motion.snapshot.lastAttempt?.id ?? null;
    const started = captureMode === 'manual'
      ? await motion.startManualCapture()
      : await motion.arm();
    setLevelActive(started);
  };

  if (motion.manualRecording) {
    return (
      <Pressable
        onPress={() => {
          const captured = motion.stopManualCapture();
          if (captured) setAttempt(captured);
          setLevelActive(false);
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

  if (levelActive && captureMode === 'auto') {
    return (
      <View style={styles.practiceAutoActive}>
        <View style={styles.practiceAutoHeader}>
          <View>
            <Text style={styles.eyebrow}>AUTO DETECTION / {definition.name}</Text>
            <Text style={styles.practiceAutoTitle}>LAND THE{`\n`}LEVEL.</Text>
          </View>
          <View style={styles.autoBadge}><Text style={styles.autoBadgeText}>AUTO</Text></View>
        </View>
        <GameStage
          frame={liveFrame}
          height={430}
          phase={motion.snapshot.phase}
          sensorHz={motion.snapshot.actualHz}
          skinColor={shellColor}
        />
        <Text style={styles.practiceAutoHint}>
          {motion.snapshot.phase === 'armed'
            ? 'Throw when ready. The level ends automatically after the catch.'
            : motion.snapshot.phase === 'airborne'
              ? 'Motion detected. Finish the rotation and catch.'
              : 'Hold steady while Kamikaze closes the capture.'}
        </Text>
        <GameButton
          label="CANCEL LEVEL"
          onPress={() => { motion.disarm(); setLevelActive(false); }}
          secondary
        />
      </View>
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
      <View style={styles.practiceModeRow}>
        <View>
          <Text style={styles.practiceModeTitle}>CAPTURE MODE</Text>
          <Text style={styles.practiceModeHelp}>{captureMode === 'auto' ? 'Stops after the catch.' : 'You stop the recording.'}</Text>
        </View>
        <View style={styles.modeSwitch}>
          {(['auto', 'manual'] as const).map((item) => (
            <Pressable
              key={item}
              onPress={() => setCaptureMode(item)}
              style={[styles.modeOption, captureMode === item && styles.modeOptionActive]}
            >
              <Text style={[styles.modeOptionText, captureMode === item && styles.modeOptionTextActive]}>{item.toUpperCase()}</Text>
            </Pressable>
          ))}
        </View>
      </View>
      {motion.sensorStatus === 'ready' ? (
        <GameButton label={levelPassed ? 'PRACTICE AGAIN' : 'START LEVEL'} onPress={startLevel} />
      ) : (
        <GameButton label="ENABLE MOTION" onPress={() => { motion.requestPermission(); }} />
      )}
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
        <GameStage frame={identityFrame} height={380} phase="idle" sensorHz={0} skinColor={selected.color} zeroable={false} />
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
  preferences,
  shellColor,
  setPreferences,
  scrollEnabled,
}: {
  catalog: TrickCatalogController;
  motion: MotionController;
  onOpenDeveloper: () => void;
  onReplayOnboarding: () => void;
  preferences: GamePreferences;
  shellColor: string;
  setPreferences: (preferences: GamePreferences) => void;
  scrollEnabled: boolean;
}) {
  const [recentExpanded, setRecentExpanded] = useState(false);
  const [selectedAttemptId, setSelectedAttemptId] = useState<string | null>(null);
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
  const selectedEntry = matches.find(({ attempt }) => attempt.id === selectedAttemptId);

  if (selectedEntry) {
    const { attempt, match } = selectedEntry;
    const matchingHistory = motion.attempts.filter((item) =>
      item.id !== attempt.id &&
      findBestTrickMatch(item, catalog.definitions).definition.id === match.definition.id,
    );
    const comparisons: RunComparison[] = [attempt, ...matchingHistory]
      .slice(0, 4)
      .map((item, index) => ({
        attempt: item,
        label: index === 0 ? 'SAVED RUN' : `PREV ${index}`,
        score: scoreFor(findBestTrickMatch(item, catalog.definitions), item),
      }));
    return (
      <ResultScreen
        attempt={attempt}
        comparisons={comparisons}
        definition={match.definition}
        match={match}
        mode="recent"
        onBack={() => setSelectedAttemptId(null)}
        scrollEnabled={scrollEnabled}
        shellColor={shellColor}
      />
    );
  }

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
        <GlassSurface fallbackColor="rgba(235,238,248,0.10)" style={styles.bigStat} tintColor="rgba(235,238,248,0.08)"><Text style={styles.bigStatValue}>{landed.length}</Text><Text style={styles.bigStatLabel}>TOTAL TRICKS</Text></GlassSurface>
        <GlassSurface fallbackColor="rgba(235,238,248,0.10)" style={styles.bigStat} tintColor="rgba(235,238,248,0.08)"><Text style={styles.bigStatValue}>{bestStreak}</Text><Text style={styles.bigStatLabel}>BEST RUN</Text></GlassSurface>
        <GlassSurface fallbackColor="rgba(235,238,248,0.10)" style={styles.bigStat} tintColor="rgba(235,238,248,0.08)"><Text style={styles.bigStatValue}>{best ? scoreFor(best.match, best.attempt) : '—'}</Text><Text style={styles.bigStatLabel}>HIGH SCORE</Text></GlassSurface>
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
      <GlassSurface fallbackColor="rgba(235,238,248,0.10)" style={styles.recordsCard} tintColor="rgba(235,238,248,0.08)">
        <View style={styles.recordRow}><Text style={styles.recordLabel}>FASTEST</Text><Text style={styles.recordValue}>{fastest ? `${(fastest.match.motionDurationMs / 1000).toFixed(2)}S` : '—'}</Text></View>
        <View style={styles.recordRow}><Text style={styles.recordLabel}>LONGEST</Text><Text style={styles.recordValue}>{longest ? `${(longest.match.motionDurationMs / 1000).toFixed(2)}S` : '—'}</Text></View>
        <View style={styles.recordRow}><Text style={styles.recordLabel}>MOST LANDED</Text><Text style={styles.recordValue}>{mostLanded?.name ?? '—'}</Text></View>
      </GlassSurface>
      <View style={styles.cardHeaderRow}>
        <Text style={styles.sectionTitle}>RECENT</Text>
        <Text style={styles.cardMeta}>{motion.historyReady ? `${motion.attempts.length} SAVED` : 'LOADING'}</Text>
      </View>
      {(recentExpanded ? matches : matches.slice(0, 6)).map(({ attempt, match }) => (
        <Pressable key={attempt.id} onPress={() => setSelectedAttemptId(attempt.id)} style={styles.recentRow}>
          <View style={styles.recentScore}><Text style={styles.recentScoreText}>{scoreFor(match, attempt)}</Text></View>
          <View style={styles.recentCopy}>
            <Text style={styles.recentName}>{match.definition.name}</Text>
            <Text style={styles.recentMeta}>{(match.motionDurationMs / 1000).toFixed(2)}S · {new Date(attempt.recordedAtIso).toLocaleDateString()}</Text>
          </View>
          <Text style={styles.recentArrow}>→</Text>
        </Pressable>
      ))}
      {matches.length > 6 && (
        <Pressable onPress={() => setRecentExpanded((expanded) => !expanded)} style={styles.recentExpand}>
          <Text style={styles.recentExpandText}>{recentExpanded ? 'COLLAPSE HISTORY' : `VIEW ALL ${matches.length} ATTEMPTS`}</Text>
          <Text style={styles.recentExpandText}>{recentExpanded ? '↑' : '↓'}</Text>
        </Pressable>
      )}
      <Text style={styles.sectionTitle}>SETTINGS</Text>
      <GlassSurface fallbackColor="rgba(235,238,248,0.10)" style={styles.settingsCard} tintColor="rgba(235,238,248,0.08)">
        <Pressable
          onPress={() => setPreferences({ ...preferences, showPerformanceHud: !preferences.showPerformanceHud })}
          style={styles.settingsRow}
        >
          <View>
            <Text style={styles.settingsText}>PERFORMANCE HUD</Text>
            <Text style={styles.settingsHint}>Live shader frame rate</Text>
          </View>
          <Text style={styles.settingsValue}>{preferences.showPerformanceHud ? 'ON' : 'OFF'}</Text>
        </Pressable>
        <Pressable
          onPress={() => catalog.setGripHand(catalog.gripHand === 'right' ? 'left' : 'right')}
          style={styles.settingsRow}
        >
          <View>
            <Text style={styles.settingsText}>GRIP HAND</Text>
            <Text style={styles.settingsHint}>Changes forward / reverse direction</Text>
          </View>
          <Text style={styles.settingsValue}>{catalog.gripHand.toUpperCase()}</Text>
        </Pressable>
        <Pressable onPress={onReplayOnboarding} style={styles.settingsRow}>
          <Text style={styles.settingsText}>REPLAY HOW TO PLAY</Text><Text style={styles.settingsArrow}>→</Text>
        </Pressable>
        <Pressable onPress={onOpenDeveloper} style={styles.settingsRow}>
          <Text style={styles.settingsText}>OPEN SENSOR WORKSHOP</Text><Text style={styles.settingsArrow}>→</Text>
        </Pressable>
      </GlassSurface>
    </ScrollView>
  );
}

function TabIcon({ active, tab }: { active: boolean; tab: GameTab }) {
  const color = active ? gameColors.volt : gameColors.frostMuted;
  if (tab === 'play') {
    return (
      <Svg height={28} viewBox="0 0 28 28" width={28}>
        <Rect fill="none" height={14} rx={3} stroke={color} strokeWidth={1.8} transform="rotate(-16 13 15)" width={8.5} x={8.75} y={8} />
        <Path d="M5.5 15.5C6.4 9.4 11.7 5.5 18 6.4" fill="none" stroke={color} strokeLinecap="round" strokeWidth={1.8} />
        <Path d="M16.2 3.9L19.5 6.5L16.2 8.7" fill="none" stroke={color} strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.8} />
      </Svg>
    );
  }
  if (tab === 'practice') {
    return (
      <Svg height={28} viewBox="0 0 28 28" width={28}>
        <Path d="M21.6 10.2A8.3 8.3 0 1 0 22 16.8" fill="none" stroke={color} strokeLinecap="round" strokeWidth={1.9} />
        <Path d="M18.5 7.2L22 10.4L18 12" fill="none" stroke={color} strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.9} />
        <Rect fill="none" height={5.5} rx={1.2} stroke={color} strokeWidth={1.5} transform="rotate(20 14 14)" width={3.5} x={12.25} y={11.25} />
      </Svg>
    );
  }
  if (tab === 'locker') {
    return (
      <Svg height={28} viewBox="0 0 28 28" width={28}>
        <Rect fill="none" height={13} rx={3} stroke={color} strokeWidth={1.5} transform="rotate(-9 12 14)" width={8} x={8} y={7.5} />
        <Rect fill={active ? 'rgba(215,255,74,0.16)' : 'none'} height={13} rx={3} stroke={color} strokeWidth={1.8} transform="rotate(9 16 14)" width={8} x={12} y={7.5} />
      </Svg>
    );
  }
  return (
    <Svg height={28} viewBox="0 0 28 28" width={28}>
      <Circle cx={14} cy={10} fill="none" r={4} stroke={color} strokeWidth={1.8} />
      <Path d="M6.8 22C7.8 17.8 10.2 16 14 16C17.8 16 20.2 17.8 21.2 22" fill="none" stroke={color} strokeLinecap="round" strokeWidth={1.8} />
    </Svg>
  );
}

function BottomNavigation({ tab, setTab }: { tab: GameTab; setTab: (tab: GameTab) => void }) {
  const tabs: { id: GameTab; label: string }[] = [
    { id: 'play', label: 'PLAY' },
    { id: 'practice', label: 'PRACTICE' },
    { id: 'locker', label: 'LOCKER' },
    { id: 'profile', label: 'ME' },
  ];
  return (
    <GlassSurface
      fallbackColor="rgba(126,140,188,0.13)"
      fallbackIntensity={78}
      glassEffectStyle="regular"
      interactive
      style={styles.bottomNav}
    >
      {tabs.map((item) => (
        <Pressable
          accessibilityRole="tab"
          accessibilityState={{ selected: tab === item.id }}
          key={item.id}
          onPress={() => setTab(item.id)}
          style={[styles.bottomTab, tab === item.id && styles.bottomTabActive]}
        >
          <TabIcon active={tab === item.id} tab={item.id} />
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
  const [shaderFps, setShaderFps] = useState(0);
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
          {!reduceTransparency && (
            <KineticBackdrop
              atmosphere={atmosphere}
              onFps={preferences.showPerformanceHud ? setShaderFps : undefined}
            />
          )}
          {preferences.showPerformanceHud && (
            <View pointerEvents="none" style={styles.performanceHud}>
              <Text style={styles.performanceHudLabel}>BACKGROUND</Text>
              <Text style={styles.performanceHudValue}>{shaderFps || '—'} FPS</Text>
              <Text style={styles.performanceHudMaterial}>{canUseLiquidGlass() ? 'LIQUID GLASS' : 'BLUR FALLBACK'}</Text>
            </View>
          )}
          <View style={styles.screenBody}>
            {tab === 'play' && (
              <PlayScreen
                catalog={catalog}
                motion={motion}
                onOpenFullCalibration={() => setShowDeveloper(true)}
                scrollEnabled={!scrollLocked}
                shellColor={selectedSkin.color}
              />
            )}
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
                preferences={preferences}
                shellColor={selectedSkin.color}
                setPreferences={setPreferences}
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
  screenBody: { flex: 1 },
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
  playScreen: { flex: 1, paddingBottom: 92, paddingHorizontal: 16, paddingTop: 6 },
  playUtilityRow: { alignItems: 'center', flexDirection: 'row', justifyContent: 'flex-end', minHeight: 38, paddingBottom: 8, paddingHorizontal: 4 },
  liveRunPill: { alignItems: 'center', backgroundColor: 'rgba(35,36,31,0.66)', borderColor: 'rgba(255,255,255,0.12)', borderRadius: 16, borderWidth: StyleSheet.hairlineWidth, flexDirection: 'row', gap: 7, paddingHorizontal: 11, paddingVertical: 8 },
  liveRunText: { color: gameColors.frost, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.7 },
  quickCalPill: { alignItems: 'center', borderRadius: 18, flexDirection: 'row', minHeight: 36, paddingHorizontal: 12 },
  quickCalDot: { backgroundColor: gameColors.volt, borderRadius: 4, height: 7, marginRight: 7, width: 7 },
  quickCalText: { color: gameColors.frost, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.7 },
  quickCalArrow: { color: gameColors.volt, fontFamily: fonts.body, fontSize: 14, marginLeft: 8 },
  recordingDot: { backgroundColor: gameColors.hazard, borderRadius: 4, height: 8, width: 8 },
  playInstructionRow: { alignItems: 'center', flexDirection: 'row', gap: 12, justifyContent: 'space-between', marginTop: 14 },
  playInstruction: { color: gameColors.frost, flex: 1, fontFamily: fonts.body, fontSize: 13, lineHeight: 18 },
  playActionDock: { flex: 1, justifyContent: 'flex-end', paddingBottom: 5 },
  modeSwitch: { backgroundColor: '#20211D', borderRadius: 18, flexDirection: 'row', padding: 3 },
  modeOption: { borderRadius: 14, paddingHorizontal: 10, paddingVertical: 7 },
  modeOptionActive: { backgroundColor: gameColors.frost },
  modeOptionText: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 7 },
  modeOptionTextActive: { color: gameColors.pitch },
  manualFullScreen: { flex: 1, paddingBottom: 92, paddingHorizontal: 16, paddingTop: 8 },
  tapAnywhere: { alignItems: 'center', flex: 1, justifyContent: 'center', paddingHorizontal: 24 },
  tapAnywhereTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 34, letterSpacing: -1.4 },
  tapAnywhereBody: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 13, lineHeight: 18, marginTop: 8, textAlign: 'center' },
  tapAnywhereAction: { color: gameColors.hazard, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 1.1, marginTop: 18 },
  resultContent: { paddingBottom: 124, paddingHorizontal: 18, paddingTop: 12 },
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
  telemetryCard: { borderRadius: gameRadii.card, marginBottom: 4, overflow: 'hidden', padding: 16 },
  telemetryHeader: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between' },
  telemetryTitle: { color: gameColors.frost, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.8 },
  telemetryMeta: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 7 },
  telemetryAxes: { flexDirection: 'row', gap: 8, marginTop: 14 },
  telemetryAxis: { backgroundColor: 'rgba(255,255,255,0.055)', borderRadius: 15, flex: 1, paddingHorizontal: 11, paddingVertical: 12 },
  telemetryAxisLabel: { color: gameColors.hazard, fontFamily: fonts.monoBold, fontSize: 7 },
  telemetryAxisValue: { color: gameColors.white, fontFamily: fonts.display, fontSize: 19, marginTop: 4 },
  telemetryRows: { marginTop: 10 },
  telemetryRow: { alignItems: 'center', borderTopColor: 'rgba(255,255,255,0.1)', borderTopWidth: StyleSheet.hairlineWidth, flexDirection: 'row', minHeight: 42 },
  telemetryRowLabel: { color: gameColors.frostMuted, flex: 1, fontFamily: fonts.mono, fontSize: 6 },
  telemetryRowValue: { color: gameColors.frost, flex: 1, fontFamily: fonts.monoBold, fontSize: 8, textAlign: 'right' },
  resultSecondaryRow: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'space-between', paddingHorizontal: 2, paddingTop: 16 },
  textAction: { padding: 8 },
  textActionLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.6 },
  screenScrollContent: { paddingBottom: 124, paddingHorizontal: 18, paddingTop: 20 },
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
  practiceModeRow: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between', marginTop: 16 },
  practiceModeTitle: { color: gameColors.frost, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.7 },
  practiceModeHelp: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 9, marginTop: 3 },
  practiceRecording: { flex: 1, justifyContent: 'center', paddingBottom: 92, paddingHorizontal: 18, paddingTop: 22 },
  practiceRecordingTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 42, letterSpacing: -1.8, lineHeight: 41, marginBottom: 18, marginTop: 10 },
  practiceRecordingTime: { color: gameColors.hazard, fontFamily: fonts.display, fontSize: 28, marginTop: 18, textAlign: 'center' },
  practiceRecordingStop: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.8, marginTop: 7, textAlign: 'center' },
  practiceAutoActive: { flex: 1, paddingBottom: 92, paddingHorizontal: 16, paddingTop: 16 },
  practiceAutoHeader: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between', marginBottom: 14 },
  practiceAutoTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 35, letterSpacing: -1.4, lineHeight: 34, marginTop: 8 },
  practiceAutoHint: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 12, lineHeight: 18, marginTop: 14 },
  autoBadge: { backgroundColor: 'rgba(215,255,74,0.14)', borderColor: gameColors.volt, borderRadius: 14, borderWidth: 1, paddingHorizontal: 11, paddingVertical: 8 },
  autoBadgeText: { color: gameColors.volt, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.8 },
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
  bigStat: { borderRadius: 20, flex: 1, paddingHorizontal: 10, paddingVertical: 15 },
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
  recordsCard: { borderRadius: gameRadii.card, marginTop: 10, paddingHorizontal: 15 },
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
  recentExpand: { alignItems: 'center', borderColor: 'rgba(255,255,255,0.14)', borderRadius: 18, borderWidth: StyleSheet.hairlineWidth, flexDirection: 'row', justifyContent: 'space-between', marginTop: 12, minHeight: 46, paddingHorizontal: 14 },
  recentExpandText: { color: gameColors.frost, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.7 },
  attemptDetailHeader: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between' },
  attemptBack: { paddingVertical: 8 },
  attemptBackText: { color: gameColors.frost, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.7 },
  attemptDetailHero: { alignItems: 'flex-end', flexDirection: 'row', justifyContent: 'space-between', marginBottom: 18, marginTop: 14 },
  attemptDetailCopy: { flex: 1, paddingBottom: 8 },
  attemptDetailName: { color: gameColors.white, fontFamily: fonts.display, fontSize: 34, letterSpacing: -1.4, lineHeight: 35 },
  attemptDetailDate: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 7, marginTop: 6 },
  attemptDetailScore: { color: gameColors.volt, fontFamily: fonts.display, fontSize: 68, letterSpacing: -3 },
  attemptMetrics: { flexDirection: 'row', gap: 8, marginTop: 12 },
  attemptMetric: { borderRadius: 18, flex: 1, paddingHorizontal: 11, paddingVertical: 13 },
  attemptMetricValue: { color: gameColors.white, fontFamily: fonts.display, fontSize: 17 },
  attemptMetricLabel: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 6, marginTop: 3 },
  attemptDetailHint: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 11, lineHeight: 16, marginTop: 13 },
  settingsCard: { borderRadius: gameRadii.card, marginTop: 10, overflow: 'hidden' },
  settingsRow: { alignItems: 'center', borderBottomColor: '#393A34', borderBottomWidth: StyleSheet.hairlineWidth, flexDirection: 'row', justifyContent: 'space-between', minHeight: 54, paddingHorizontal: 15 },
  settingsText: { color: gameColors.frost, fontFamily: fonts.bodyBold, fontSize: 10 },
  settingsHint: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 8, marginTop: 3 },
  settingsValue: { color: gameColors.volt, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.6 },
  settingsArrow: { color: gameColors.frostMuted, fontSize: 16 },
  bottomNav: { alignItems: 'center', borderRadius: 34, bottom: 8, elevation: 20, flexDirection: 'row', height: 78, left: 12, padding: 6, position: 'absolute', right: 12, zIndex: 20 },
  bottomTab: { alignItems: 'center', borderRadius: 27, flex: 1, height: 64, justifyContent: 'center' },
  bottomTabActive: { backgroundColor: 'rgba(255,255,255,0.07)', borderColor: 'rgba(255,255,255,0.14)', borderWidth: StyleSheet.hairlineWidth },
  bottomLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.5, marginTop: 3 },
  bottomLabelActive: { color: gameColors.white },
  performanceHud: { alignItems: 'flex-end', backgroundColor: 'rgba(8,9,12,0.68)', borderColor: 'rgba(215,255,74,0.35)', borderRadius: 12, borderWidth: StyleSheet.hairlineWidth, paddingHorizontal: 10, paddingVertical: 7, position: 'absolute', right: 18, top: 10, zIndex: 30 },
  performanceHudLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 6, letterSpacing: 0.7 },
  performanceHudValue: { color: gameColors.volt, fontFamily: fonts.monoBold, fontSize: 9, marginTop: 2 },
  performanceHudMaterial: { color: gameColors.frostMuted, fontFamily: fonts.mono, fontSize: 6, letterSpacing: 0.5, marginTop: 3 },
  developerContent: { paddingBottom: 40, paddingHorizontal: 20, paddingTop: 10 },
  developerHeader: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between' },
  developerTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 28, marginTop: 5 },
  developerClose: { backgroundColor: gameColors.frost, borderRadius: 18, paddingHorizontal: 14, paddingVertical: 10 },
  developerCloseText: { color: gameColors.pitch, fontFamily: fonts.monoBold, fontSize: 8 },
});
