import { useEffect, useMemo, useRef, useState } from 'react';
import { PanResponder, Pressable, StyleSheet, Text, View } from 'react-native';

import { useMotionLab } from '../hooks/useMotionLab';
import {
  analyzeCalibrationCapture,
  buildCalibrationReplayFrames,
  CALIBRATION_STEPS,
  type CalibrationResult,
  type CalibrationStep,
  summarizeCalibration,
} from '../motion/calibration';
import { quaternionFromEulerDegrees } from '../motion/replay';
import type { ReplayFrame, Vector3 } from '../motion/types';
import {
  appendCalibrationCapture,
  loadCalibrationCaptures,
  type StoredCalibrationCapture,
} from '../storage/calibrationHistory';
import { colors, fonts } from '../theme';
import { PhoneScene3D } from './PhoneScene3D';
import { useScrollLock } from './ScrollLock';

type Phase = 'demo' | 'countdown' | 'recording' | 'result' | 'summary';

const DEMO_CAMERA = { azimuth: -0.16, elevation: 0.02, distance: 5.1 };
const MIN_MOVE_WINDOW_MS = 1000;
const MAX_MOVE_WINDOW_MS = 5000;
const PLAYBACK_SPEEDS = [1, 0.5, 0.25] as const;
const delay = (milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const clamp = (value: number, minimum: number, maximum: number) =>
  Math.min(maximum, Math.max(minimum, value));

const axisVector = (step: CalibrationStep, progress: number): Vector3 => ({
  x: step.axis === 'x' ? step.degrees * step.direction * progress : 0,
  y: step.axis === 'y' ? step.degrees * step.direction * progress : 0,
  z: step.axis === 'z' ? step.degrees * step.direction * progress : 0,
});

const movementName = (step: CalibrationStep) => {
  if (step.axis === 'z') return 'FLAT SPIN / SHUVIT AXIS';
  if (step.axis === 'x') return 'WIDTH AXIS ROTATION';
  return 'LONG-EDGE AXIS ROTATION';
};

function ResultPanel({ result, step }: { result: CalibrationResult; step: CalibrationStep }) {
  const measured = result.measuredDegrees;
  const measuredDominant = measured[result.dominantAxis];
  return (
    <View style={[styles.resultPanel, result.pass ? styles.resultPass : styles.resultReview]}>
      <View style={styles.verdictRow}>
        <View>
          <Text style={styles.resultKicker}>{result.pass ? 'AXIS MATCH' : 'REVIEW MAPPING'}</Text>
          <Text style={styles.verdict}>{result.pass ? 'PASS.' : 'MISMATCH.'}</Text>
        </View>
        <Text style={styles.score}>{Math.round(result.score * 100)}</Text>
      </View>
      <View style={styles.comparisonRow}>
        <View style={styles.comparisonCell}>
          <Text style={styles.comparisonLabel}>EXPECTED</Text>
          <Text style={styles.comparisonValue}>
            {step.axis.toUpperCase()}{step.direction > 0 ? '+' : '−'}{step.degrees}°
          </Text>
        </View>
        <View style={styles.comparisonCell}>
          <Text style={styles.comparisonLabel}>MEASURED</Text>
          <Text style={styles.comparisonValue}>
            {result.dominantAxis.toUpperCase()}{measuredDominant >= 0 ? '+' : '−'}{Math.abs(Math.round(measuredDominant))}°
          </Text>
        </View>
      </View>
      <View style={styles.metricLine}>
        <Text style={styles.metricText}>DOMINANCE {Math.round((1 - result.crossTalk) * 100)}%</Text>
        <Text style={styles.metricText}>CROSS-TALK {Math.round(result.crossTalk * 100)}%</Text>
        <Text style={styles.metricText}>{result.sampleCount} RAW</Text>
      </View>
    </View>
  );
}

function PlaybackIcon({ playing }: { playing: boolean }) {
  if (playing) {
    return (
      <View style={styles.pauseIcon}>
        <View style={styles.pauseBar} />
        <View style={styles.pauseBar} />
      </View>
    );
  }
  return <View style={styles.playTriangle} />;
}

export function CalibrationBench({ motion }: { motion: ReturnType<typeof useMotionLab> }) {
  const [stepIndex, setStepIndex] = useState(0);
  const [phase, setPhase] = useState<Phase>('demo');
  const [countdown, setCountdown] = useState(3);
  const [cue, setCue] = useState<'hold' | 'move'>('hold');
  const [demoProgress, setDemoProgress] = useState(0);
  const [results, setResults] = useState<CalibrationResult[]>([]);
  const [currentResult, setCurrentResult] = useState<CalibrationResult | null>(null);
  const [moveWindowMs, setMoveWindowMs] = useState(1950);
  const [replayFrames, setReplayFrames] = useState<ReplayFrame[]>([]);
  const [replayProgress, setReplayProgress] = useState(0);
  const [replayPlaying, setReplayPlaying] = useState(false);
  const [replaySpeed, setReplaySpeed] = useState<(typeof PLAYBACK_SPEEDS)[number]>(1);
  const [captures, setCaptures] = useState<StoredCalibrationCapture[]>([]);
  const [historyReady, setHistoryReady] = useState(false);
  const [selectedCaptureId, setSelectedCaptureId] = useState<string | null>(null);
  const [profileApplied, setProfileApplied] = useState(false);
  const runIdRef = useRef(0);
  const paceWidthRef = useRef(1);
  const paceOriginXRef = useRef(0);
  const replayWidthRef = useRef(1);
  const replayOriginXRef = useRef(0);
  const setScrollLocked = useScrollLock();
  const step = CALIBRATION_STEPS[stepIndex] ?? CALIBRATION_STEPS[0];

  useEffect(() => {
    setMoveWindowMs(step.tempo === 'slow' ? 1950 : 1450);
  }, [step.id, step.tempo]);

  useEffect(() => {
    let active = true;
    loadCalibrationCaptures().then((stored) => {
      if (!active) return;
      setCaptures(stored);
      const seen = new Set<string>();
      const latestResults = stored
        .filter((capture) => {
          if (seen.has(capture.step.id)) return false;
          seen.add(capture.step.id);
          return true;
        })
        .map((capture) => capture.result);
      setResults(latestResults);
      const completed = new Set(stored.map((capture) => capture.step.id));
      const firstPending = CALIBRATION_STEPS.findIndex((candidate) => !completed.has(candidate.id));
      if (firstPending >= 0) setStepIndex(firstPending);
      setHistoryReady(true);
    });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (phase !== 'demo') return;
    const timer = setInterval(() => {
      const cycleDuration = moveWindowMs + 720;
      const cycle = Date.now() % cycleDuration;
      setDemoProgress(cycle < moveWindowMs ? cycle / moveWindowMs : 1);
    }, 33);
    return () => clearInterval(timer);
  }, [moveWindowMs, phase]);

  useEffect(() => {
    if (phase !== 'result' || !replayPlaying || replayFrames.length === 0) return;
    let previous = Date.now();
    const durationMs = Math.max(replayFrames.at(-1)?.timestampMs ?? 1, 1);
    const timer = setInterval(() => {
      const now = Date.now();
      const delta = now - previous;
      previous = now;
      setReplayProgress((value) => {
        const nextProgress = value + delta * replaySpeed / durationMs;
        if (nextProgress >= 1) {
          setReplayPlaying(false);
          return 1;
        }
        return nextProgress;
      });
    }, 33);
    return () => clearInterval(timer);
  }, [phase, replayFrames, replayPlaying, replaySpeed]);

  useEffect(() => () => setScrollLocked(false), [setScrollLocked]);

  useEffect(() => () => {
    runIdRef.current += 1;
    motion.stopCalibrationCapture();
  }, [motion.stopCalibrationCapture]);

  const replayDurationMs = Math.max(replayFrames.at(-1)?.timestampMs ?? moveWindowMs + 420, 1);
  const expectedReplayProgress = phase === 'result'
    ? clamp((replayProgress * replayDurationMs - 420) / moveWindowMs, 0, 1)
    : 0;
  const visibleProgress = phase === 'demo'
    ? demoProgress
    : phase === 'result'
      ? expectedReplayProgress
      : 0;
  const targetEuler = axisVector(step, visibleProgress);
  const targetFrame: ReplayFrame = {
    accelG: 1,
    gyroDps: 0,
    progress: 0.5,
    quaternion: quaternionFromEulerDegrees(targetEuler),
    timestampMs: visibleProgress * 1000,
  };
  const replayFrameIndex = Math.min(
    replayFrames.length - 1,
    Math.round(replayProgress * Math.max(0, replayFrames.length - 1)),
  );
  const actualReplayFrame = replayFrames[replayFrameIndex] ?? targetFrame;

  const updatePace = (pageX: number) => {
    const ratio = clamp((pageX - paceOriginXRef.current) / paceWidthRef.current, 0, 1);
    setMoveWindowMs(Math.round((MIN_MOVE_WINDOW_MS + ratio * (MAX_MOVE_WINDOW_MS - MIN_MOVE_WINDOW_MS)) / 50) * 50);
  };
  const paceResponder = useMemo(() => PanResponder.create({
    onMoveShouldSetPanResponder: () => true,
    onStartShouldSetPanResponder: () => true,
    onPanResponderGrant: (event) => {
      setScrollLocked(true);
      paceOriginXRef.current = event.nativeEvent.pageX - event.nativeEvent.locationX;
      updatePace(event.nativeEvent.pageX);
    },
    onPanResponderMove: (event) => updatePace(event.nativeEvent.pageX),
    onPanResponderRelease: () => setScrollLocked(false),
    onPanResponderTerminate: () => setScrollLocked(false),
    onPanResponderTerminationRequest: () => false,
  }), [setScrollLocked]);

  const updateReplay = (pageX: number) => {
    setReplayPlaying(false);
    setReplayProgress(clamp((pageX - replayOriginXRef.current) / replayWidthRef.current, 0, 1));
  };
  const replayResponder = useMemo(() => PanResponder.create({
    onMoveShouldSetPanResponder: () => true,
    onStartShouldSetPanResponder: () => true,
    onPanResponderGrant: (event) => {
      setScrollLocked(true);
      replayOriginXRef.current = event.nativeEvent.pageX - event.nativeEvent.locationX;
      updateReplay(event.nativeEvent.pageX);
    },
    onPanResponderMove: (event) => updateReplay(event.nativeEvent.pageX),
    onPanResponderRelease: () => setScrollLocked(false),
    onPanResponderTerminate: () => setScrollLocked(false),
    onPanResponderTerminationRequest: () => false,
  }), [setScrollLocked]);

  const startTest = async () => {
    const connected = motion.sensorStatus === 'ready' || await motion.requestPermission();
    if (!connected) return;

    const runId = runIdRef.current + 1;
    runIdRef.current = runId;
    setCurrentResult(null);
    setSelectedCaptureId(null);
    setPhase('countdown');

    for (const count of [3, 2, 1]) {
      if (runIdRef.current !== runId) return;
      setCountdown(count);
      await delay(620);
    }

    if (runIdRef.current !== runId) return;
    motion.startCalibrationCapture();
    setCue('hold');
    setPhase('recording');
    await delay(420);
    if (runIdRef.current !== runId) return;
    setCue('move');
    await delay(moveWindowMs);
    if (runIdRef.current !== runId) return;

    const samples = motion.stopCalibrationCapture();
    const result = analyzeCalibrationCapture(samples, step);
    const capturedFrames = buildCalibrationReplayFrames(samples, result.biasDps);
    const capture: StoredCalibrationCapture = {
      id: `${Date.now()}-${step.id}`,
      recordedAtIso: new Date().toISOString(),
      result,
      samples,
      step,
    };
    appendCalibrationCapture(capture).catch(() => undefined);
    setCaptures((existing) => [capture, ...existing.filter(({ id }) => id !== capture.id)].slice(0, 80));
    setSelectedCaptureId(capture.id);
    setCurrentResult(result);
    setReplayFrames(capturedFrames);
    setReplayProgress(0);
    setReplayPlaying(true);
    setResults((existing) => [
      ...existing.filter(({ stepId }) => stepId !== result.stepId),
      result,
    ]);
    setPhase('result');
  };

  const retry = () => {
    runIdRef.current += 1;
    motion.stopCalibrationCapture();
    setCurrentResult(null);
    setSelectedCaptureId(null);
    setReplayFrames([]);
    setReplayPlaying(false);
    setDemoProgress(0);
    setPhase('demo');
  };

  const openCapture = (capture: StoredCalibrationCapture) => {
    const captureStepIndex = CALIBRATION_STEPS.findIndex(({ id }) => id === capture.step.id);
    if (captureStepIndex >= 0) setStepIndex(captureStepIndex);
    const frames = buildCalibrationReplayFrames(capture.samples, capture.result.biasDps);
    setCurrentResult(capture.result);
    setReplayFrames(frames);
    setReplayProgress(0);
    setReplayPlaying(true);
    setSelectedCaptureId(capture.id);
    setPhase('result');
  };

  const goToStep = (nextIndex: number, openSaved = true) => {
    const boundedIndex = clamp(nextIndex, 0, CALIBRATION_STEPS.length - 1);
    const nextStep = CALIBRATION_STEPS[boundedIndex];
    if (openSaved) {
      const saved = captures.find((capture) => capture.step.id === nextStep.id);
      if (saved) {
        openCapture(saved);
        return;
      }
    }
    setStepIndex(boundedIndex);
    setCurrentResult(null);
    setSelectedCaptureId(null);
    setReplayFrames([]);
    setReplayPlaying(false);
    setDemoProgress(0);
    setPhase('demo');
  };

  const next = () => {
    if (stepIndex >= CALIBRATION_STEPS.length - 1) {
      setPhase('summary');
      return;
    }
    goToStep(stepIndex + 1, false);
  };

  const summary = useMemo(() => summarizeCalibration(results), [results]);
  const summaryReady = new Set(summary.map(({ rawAxis }) => rawAxis)).size === 3 &&
    summary.every(({ confidence }) => confidence >= 0.5);

  if (phase === 'summary') {
    return (
      <View style={styles.shell}>
        <Text style={styles.pageKicker}>CAL / SESSION COMPLETE</Text>
        <Text style={styles.pageTitle}>AXIS{`\n`}FINGERPRINT.</Text>
        <Text style={styles.intro}>Candidate mapping calculated from {results.length} controlled rotations.</Text>
        <View style={styles.summaryPanel}>
          {summary.map((axis) => (
            <View key={axis.logicalAxis} style={styles.mappingRow}>
              <Text style={styles.mappingLogical}>{axis.logicalAxis.toUpperCase()}</Text>
              <Text style={styles.mappingArrow}>←</Text>
              <Text style={styles.mappingRaw}>
                {axis.sign > 0 ? '+' : '−'}{axis.rawAxis.toUpperCase()} × {axis.gain.toFixed(2)}
              </Text>
              <Text style={styles.mappingConfidence}>{Math.round(axis.confidence * 100)}%</Text>
            </View>
          ))}
        </View>
        <Text style={styles.summaryNote}>
          {profileApplied
            ? 'This precision axis map is now active in Play and Practice.'
            : 'Apply only when every logical axis maps to a unique raw axis with useful confidence.'}
        </Text>
        <Pressable
          disabled={!summaryReady}
          onPress={() => {
            motion.applyCalibrationProfile(summary);
            setProfileApplied(true);
          }}
          style={[styles.primaryButton, !summaryReady && styles.stepArrowDisabled]}
        >
          <Text style={styles.primaryText}>{profileApplied ? 'CALIBRATION APPLIED' : 'APPLY PRECISION CALIBRATION'}</Text>
          <Text style={styles.primaryText}>✓</Text>
        </Pressable>
        {captures[0] && (
          <Pressable onPress={() => openCapture(captures[0])} style={styles.secondarySummaryButton}>
            <Text style={styles.secondaryText}>REVIEW CAL TAPE</Text>
            <Text style={styles.secondaryText}>→</Text>
          </Pressable>
        )}
        <Pressable
          onPress={() => {
            setResults([]);
            setStepIndex(0);
            setPhase('demo');
          }}
          style={styles.primaryButton}
        >
          <Text style={styles.primaryText}>RUN AGAIN</Text>
          <Text style={styles.primaryText}>↻</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={styles.shell}>
      <View style={styles.pageHeader}>
        <View>
          <Text style={styles.pageKicker}>CAL / AXIS BENCH</Text>
          <Text style={styles.pageTitle}>COPY THE{`\n`}BLUE PHONE.</Text>
        </View>
        <View style={styles.stepNavigator}>
          <Pressable
            disabled={stepIndex === 0}
            onPress={() => goToStep(stepIndex - 1)}
            style={[styles.stepArrow, stepIndex === 0 && styles.stepArrowDisabled]}
          >
            <Text style={styles.stepArrowText}>←</Text>
          </Pressable>
          <View style={styles.stepBadge}>
            <Text style={styles.stepNumber}>{String(stepIndex + 1).padStart(2, '0')}</Text>
            <Text style={styles.stepTotal}>/ {CALIBRATION_STEPS.length}</Text>
          </View>
          <Pressable
            disabled={stepIndex === CALIBRATION_STEPS.length - 1}
            onPress={() => goToStep(stepIndex + 1)}
            style={[styles.stepArrow, stepIndex === CALIBRATION_STEPS.length - 1 && styles.stepArrowDisabled]}
          >
            <Text style={styles.stepArrowText}>→</Text>
          </Pressable>
        </View>
      </View>

      <View style={styles.protocolCard}>
        <View style={styles.protocolTopline}>
          <Text style={styles.protocolAxis}>
            {step.axis.toUpperCase()}{step.direction > 0 ? '+' : '−'} / {step.degrees}°
          </Text>
          <Text style={styles.protocolTempo}>{step.tempo.toUpperCase()}</Text>
        </View>
        <Text style={styles.protocolName}>{movementName(step)}</Text>
        <Text style={styles.protocolInstruction}>
          Hold over something soft. Copy the model once, then stop completely.
        </Text>
        <View style={styles.paceHeader}>
          <Text style={styles.paceLabel}>MOVE WINDOW</Text>
          <Text style={styles.paceValue}>{(moveWindowMs / 1000).toFixed(2)}S</Text>
        </View>
        <View
          {...paceResponder.panHandlers}
          onLayout={(event) => { paceWidthRef.current = event.nativeEvent.layout.width; }}
          style={styles.sliderTouch}
        >
          <View style={styles.sliderTrack}>
            <View
              style={[
                styles.sliderFill,
                { width: `${(moveWindowMs - MIN_MOVE_WINDOW_MS) / (MAX_MOVE_WINDOW_MS - MIN_MOVE_WINDOW_MS) * 100}%` },
              ]}
            />
            <View
              style={[
                styles.sliderThumb,
                { left: `${(moveWindowMs - MIN_MOVE_WINDOW_MS) / (MAX_MOVE_WINDOW_MS - MIN_MOVE_WINDOW_MS) * 100}%` },
              ]}
            />
          </View>
        </View>
        <View style={styles.paceRange}>
          <Text style={styles.paceRangeText}>1.0S</Text>
          <Text style={styles.paceRangeText}>5.0S</Text>
        </View>
      </View>

      <View style={styles.stage}>
        <PhoneScene3D
          camera={DEMO_CAMERA}
          comparisonFrame={phase === 'result' && replayFrames.length > 0 ? targetFrame : undefined}
          frame={phase === 'result' && replayFrames.length > 0 ? actualReplayFrame : targetFrame}
          tone="blue"
          variant="pose"
        />
        {phase === 'countdown' && (
          <View style={styles.cueOverlay}>
            <Text style={styles.countdown}>{countdown}</Text>
            <Text style={styles.cueSmall}>GET READY</Text>
          </View>
        )}
        {phase === 'recording' && (
          <View style={[styles.cueOverlay, cue === 'move' && styles.cueOverlayMove]}>
            <Text style={styles.cueWord}>{cue === 'hold' ? 'HOLD.' : 'MOVE.'}</Text>
            <Text style={styles.cueSmall}>{cue === 'hold' ? 'MEASURING BIAS' : 'ONE CLEAN ROTATION'}</Text>
          </View>
        )}
        {phase === 'demo' && (
          <View pointerEvents="none" style={styles.demoLabelRow}>
            <Text style={styles.demoLabel}>WATCH DIRECTION</Text>
            <Text style={styles.demoLabel}>THEN COPY ONCE</Text>
          </View>
        )}
        {phase === 'result' && replayFrames.length > 0 && (
          <View pointerEvents="none" style={styles.comparisonLabels}>
            <Text style={styles.actualLabel}>● ACTUAL</Text>
            <Text style={styles.targetLabel}>● TARGET</Text>
          </View>
        )}
      </View>

      {phase === 'result' && replayFrames.length > 0 && (
        <View style={styles.replayTransport}>
          <Pressable
            accessibilityLabel={replayPlaying ? 'Pause calibration replay' : 'Play calibration replay'}
            onPress={() => {
              if (replayProgress >= 1) setReplayProgress(0);
              setReplayPlaying((value) => !value || replayProgress >= 1);
            }}
            style={styles.replayButton}
          >
            <PlaybackIcon playing={replayPlaying} />
          </Pressable>
          <View style={styles.replayTimelineColumn}>
            <View style={styles.replayTimes}>
              <Text style={styles.replayTime}>{Math.round(replayProgress * replayDurationMs)}MS</Text>
              <Text style={styles.replayTime}>{Math.round(replayDurationMs)}MS</Text>
            </View>
            <View
              {...replayResponder.panHandlers}
              onLayout={(event) => { replayWidthRef.current = event.nativeEvent.layout.width; }}
              style={styles.replayTimelineTouch}
            >
              <View style={styles.replayTrack}>
                <View style={[styles.replayFill, { width: `${replayProgress * 100}%` }]} />
                <View style={[styles.replayThumb, { left: `${replayProgress * 100}%` }]} />
              </View>
            </View>
          </View>
          <Pressable
            accessibilityLabel={`Calibration playback speed ${replaySpeed} times`}
            onPress={() => {
              const index = PLAYBACK_SPEEDS.indexOf(replaySpeed);
              setReplaySpeed(PLAYBACK_SPEEDS[(index + 1) % PLAYBACK_SPEEDS.length]);
            }}
            style={styles.speedButton}
          >
            <Text style={styles.speedValue}>{replaySpeed}×</Text>
            <Text style={styles.speedLabel}>SPEED</Text>
          </Pressable>
        </View>
      )}

      {currentResult && <ResultPanel result={currentResult} step={step} />}

      {phase === 'result' ? (
        <View style={styles.actionRow}>
          <Pressable onPress={retry} style={styles.secondaryButton}>
            <Text style={styles.secondaryText}>RETRY</Text>
          </Pressable>
          <Pressable onPress={next} style={[styles.primaryButton, styles.nextButton]}>
            <Text style={styles.primaryText}>{stepIndex === CALIBRATION_STEPS.length - 1 ? 'RESULTS' : 'NEXT TEST'}</Text>
            <Text style={styles.primaryText}>→</Text>
          </Pressable>
        </View>
      ) : (
        <Pressable
          disabled={phase !== 'demo'}
          onPress={startTest}
          style={[styles.primaryButton, phase !== 'demo' && styles.buttonDisabled]}
        >
          <Text style={styles.primaryText}>{motion.sensorStatus === 'ready' ? 'START CAPTURE' : 'ENABLE + START'}</Text>
          <Text style={styles.primaryText}>●</Text>
        </Pressable>
      )}

      <View style={styles.tapeHeader}>
        <Text style={styles.tapeTitle}>CAL TAPE</Text>
        <Text style={styles.tapeCount}>{historyReady ? `${captures.length} SAVED` : 'LOADING'}</Text>
      </View>
      {captures.length > 0 ? captures.slice(0, 12).map((capture) => {
        const measuredAxis = capture.result.dominantAxis;
        const measured = capture.result.measuredDegrees[measuredAxis];
        const time = new Date(capture.recordedAtIso).toLocaleTimeString([], {
          hour: '2-digit',
          minute: '2-digit',
        });
        const selected = selectedCaptureId === capture.id;
        return (
          <Pressable
            key={capture.id}
            onPress={() => openCapture(capture)}
            style={[styles.tapeRow, selected && styles.tapeRowSelected]}
          >
            <View style={styles.tapeTimeBox}>
              <Text style={[styles.tapeTime, selected && styles.tapeTextSelected]}>{time}</Text>
            </View>
            <View style={styles.tapeCopy}>
              <Text style={[styles.tapeProtocol, selected && styles.tapeTextSelected]}>
                {capture.step.axis.toUpperCase()}{capture.step.direction > 0 ? '+' : '−'}{capture.step.degrees}°
                {'  →  '}
                {measuredAxis.toUpperCase()}{measured >= 0 ? '+' : '−'}{Math.abs(Math.round(measured))}°
              </Text>
              <Text style={[styles.tapeMeta, selected && styles.tapeMetaSelected]}>
                {capture.result.pass ? 'PASS' : 'REVIEW'} · {capture.samples.length} RAW · {Math.round(capture.result.score * 100)} SCORE
              </Text>
            </View>
            <Text style={[styles.tapeOpen, selected && styles.tapeTextSelected]}>→</Text>
          </Pressable>
        );
      }) : (
        <View style={styles.tapeEmpty}>
          <Text style={styles.tapeEmptyText}>THE FIRST COMPLETED CAPTURE WILL APPEAR HERE.</Text>
        </View>
      )}

      <Text style={styles.safety}>SOFT SURFACE ONLY · ONE MOTION PER CAPTURE · DO NOT THROW DURING CALIBRATION</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  shell: { paddingTop: 27 },
  pageHeader: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between' },
  pageKicker: { color: colors.cobalt, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 1.4 },
  pageTitle: { color: colors.asphalt, fontFamily: fonts.display, fontSize: 39, letterSpacing: -1.8, lineHeight: 38, marginTop: 9 },
  intro: { color: colors.asphalt, fontFamily: fonts.body, fontSize: 13, lineHeight: 19, marginTop: 12 },
  stepNavigator: { alignItems: 'center', flexDirection: 'row', gap: 4 },
  stepArrow: { alignItems: 'center', borderColor: colors.asphalt, borderWidth: 1, height: 32, justifyContent: 'center', width: 27 },
  stepArrowDisabled: { opacity: 0.22 },
  stepArrowText: { color: colors.asphalt, fontFamily: fonts.bodyBold, fontSize: 13 },
  stepBadge: { alignItems: 'baseline', backgroundColor: colors.coral, flexDirection: 'row', paddingHorizontal: 11, paddingVertical: 10, transform: [{ rotate: '2deg' }] },
  stepNumber: { color: colors.white, fontFamily: fonts.display, fontSize: 24 },
  stepTotal: { color: colors.white, fontFamily: fonts.monoBold, fontSize: 8, marginLeft: 3 },
  protocolCard: { borderColor: colors.asphalt, borderWidth: 1.5, marginTop: 22, padding: 15 },
  protocolTopline: { alignItems: 'center', flexDirection: 'row', justifyContent: 'space-between' },
  protocolAxis: { color: colors.coral, fontFamily: fonts.display, fontSize: 23 },
  protocolTempo: { color: colors.concrete, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 1 },
  protocolName: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 0.8, marginTop: 6 },
  protocolInstruction: { color: colors.concrete, fontFamily: fonts.body, fontSize: 11, lineHeight: 16, marginTop: 6 },
  paceHeader: { alignItems: 'center', borderTopColor: '#D2D1C9', borderTopWidth: 1, flexDirection: 'row', justifyContent: 'space-between', marginTop: 13, paddingTop: 10 },
  paceLabel: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.8 },
  paceValue: { color: colors.cobalt, fontFamily: fonts.monoBold, fontSize: 11 },
  sliderTouch: { height: 28, justifyContent: 'center' },
  sliderTrack: { backgroundColor: '#D4D3CB', height: 3, position: 'relative' },
  sliderFill: { backgroundColor: colors.cobalt, height: 3 },
  sliderThumb: { backgroundColor: colors.coral, height: 15, marginLeft: -7, marginTop: -9, position: 'absolute', top: 0, width: 14 },
  paceRange: { flexDirection: 'row', justifyContent: 'space-between', marginTop: -3 },
  paceRangeText: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 6 },
  stage: { backgroundColor: colors.asphalt, height: 365, marginTop: 11, overflow: 'hidden', position: 'relative' },
  cueOverlay: { ...StyleSheet.absoluteFillObject, alignItems: 'center', backgroundColor: 'rgba(23,24,19,0.82)', justifyContent: 'center' },
  cueOverlayMove: { backgroundColor: 'rgba(73,103,255,0.88)' },
  countdown: { color: colors.white, fontFamily: fonts.display, fontSize: 92, lineHeight: 95 },
  cueWord: { color: colors.white, fontFamily: fonts.display, fontSize: 57, letterSpacing: -2 },
  cueSmall: { color: colors.white, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 1.3, marginTop: 4 },
  demoLabelRow: { bottom: 11, flexDirection: 'row', justifyContent: 'space-between', left: 12, position: 'absolute', right: 12 },
  demoLabel: { color: '#898A81', fontFamily: fonts.mono, fontSize: 6, letterSpacing: 0.55 },
  comparisonLabels: { bottom: 11, flexDirection: 'row', justifyContent: 'space-around', left: 22, position: 'absolute', right: 22 },
  actualLabel: { color: colors.cobalt, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.7 },
  targetLabel: { color: colors.coral, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.7 },
  replayTransport: { alignItems: 'center', backgroundColor: '#23241F', borderTopColor: '#41423C', borderTopWidth: 1, flexDirection: 'row', gap: 7, paddingHorizontal: 12, paddingVertical: 12 },
  replayButton: { alignItems: 'center', backgroundColor: colors.white, height: 48, justifyContent: 'center', width: 48 },
  pauseIcon: { flexDirection: 'row', gap: 5 },
  pauseBar: { backgroundColor: colors.asphalt, height: 18, width: 5 },
  playTriangle: { borderBottomColor: 'transparent', borderBottomWidth: 10, borderLeftColor: colors.asphalt, borderLeftWidth: 16, borderTopColor: 'transparent', borderTopWidth: 10, marginLeft: 3 },
  speedButton: { alignItems: 'center', borderColor: '#55564E', borderWidth: 1, height: 48, justifyContent: 'center', width: 52 },
  speedValue: { color: colors.white, fontFamily: fonts.monoBold, fontSize: 11 },
  speedLabel: { color: '#85867D', fontFamily: fonts.monoBold, fontSize: 5, letterSpacing: 0.8, marginTop: 2 },
  replayTimelineColumn: { flex: 1 },
  replayTimes: { flexDirection: 'row', justifyContent: 'space-between' },
  replayTime: { color: '#96978D', fontFamily: fonts.mono, fontSize: 7 },
  replayTimelineTouch: { height: 44, justifyContent: 'center' },
  replayTrack: { backgroundColor: '#4A4B45', height: 5, position: 'relative' },
  replayFill: { backgroundColor: colors.white, height: 5 },
  replayThumb: { backgroundColor: colors.coral, borderColor: colors.white, borderWidth: 2, height: 22, marginLeft: -11, marginTop: -13.5, position: 'absolute', top: 0, width: 22 },
  resultPanel: { borderWidth: 1.5, marginTop: 11, padding: 14 },
  resultPass: { backgroundColor: '#E9EDE3', borderColor: colors.asphalt },
  resultReview: { backgroundColor: '#FFE4DF', borderColor: colors.coral },
  verdictRow: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between' },
  resultKicker: { color: colors.coral, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 1 },
  verdict: { color: colors.asphalt, fontFamily: fonts.display, fontSize: 27, marginTop: 2 },
  score: { color: colors.asphalt, fontFamily: fonts.display, fontSize: 37 },
  comparisonRow: { borderTopColor: colors.asphalt, borderTopWidth: 1, flexDirection: 'row', marginTop: 10 },
  comparisonCell: { flex: 1, paddingTop: 9 },
  comparisonLabel: { color: colors.concrete, fontFamily: fonts.monoBold, fontSize: 7 },
  comparisonValue: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 13, marginTop: 3 },
  metricLine: { flexDirection: 'row', justifyContent: 'space-between', marginTop: 11 },
  metricText: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 6 },
  actionRow: { flexDirection: 'row', gap: 8, marginTop: 10 },
  primaryButton: { alignItems: 'center', backgroundColor: colors.cobalt, borderColor: colors.asphalt, borderWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', marginTop: 11, paddingHorizontal: 16, paddingVertical: 16 },
  nextButton: { flex: 1, marginTop: 0 },
  primaryText: { color: colors.white, fontFamily: fonts.bodyBold, fontSize: 12, letterSpacing: 0.5 },
  secondaryButton: { alignItems: 'center', borderColor: colors.asphalt, borderWidth: 1.5, justifyContent: 'center', paddingHorizontal: 18 },
  secondaryText: { color: colors.asphalt, fontFamily: fonts.bodyBold, fontSize: 11 },
  buttonDisabled: { opacity: 0.45 },
  tapeHeader: { alignItems: 'center', borderBottomColor: colors.asphalt, borderBottomWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', marginTop: 27, paddingBottom: 10 },
  tapeTitle: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 9, letterSpacing: 1.2 },
  tapeCount: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 8 },
  tapeRow: { alignItems: 'center', borderBottomColor: colors.asphalt, borderBottomWidth: 1, flexDirection: 'row', minHeight: 61 },
  tapeRowSelected: { backgroundColor: colors.cobalt },
  tapeTimeBox: { width: 54 },
  tapeTime: { color: colors.concrete, fontFamily: fonts.monoBold, fontSize: 7 },
  tapeCopy: { flex: 1 },
  tapeProtocol: { color: colors.asphalt, fontFamily: fonts.monoBold, fontSize: 10 },
  tapeMeta: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 6, marginTop: 4 },
  tapeTextSelected: { color: colors.white },
  tapeMetaSelected: { color: '#DCE2FF' },
  tapeOpen: { color: colors.asphalt, fontFamily: fonts.bodyBold, fontSize: 14, paddingLeft: 8 },
  tapeEmpty: { borderBottomColor: colors.asphalt, borderBottomWidth: 1, paddingVertical: 18 },
  tapeEmptyText: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 7, letterSpacing: 0.4 },
  safety: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 7, lineHeight: 11, marginTop: 12, textAlign: 'center' },
  summaryPanel: { borderColor: colors.asphalt, borderWidth: 1.5, marginTop: 22 },
  mappingRow: { alignItems: 'center', borderBottomColor: colors.asphalt, borderBottomWidth: 1, flexDirection: 'row', minHeight: 63, paddingHorizontal: 14 },
  mappingLogical: { color: colors.coral, fontFamily: fonts.display, fontSize: 24, width: 40 },
  mappingArrow: { color: colors.concrete, fontFamily: fonts.body, fontSize: 18, marginRight: 12 },
  mappingRaw: { color: colors.asphalt, flex: 1, fontFamily: fonts.monoBold, fontSize: 12 },
  mappingConfidence: { color: colors.concrete, fontFamily: fonts.mono, fontSize: 9 },
  summaryNote: { color: colors.concrete, fontFamily: fonts.body, fontSize: 11, lineHeight: 16, marginTop: 13 },
  secondarySummaryButton: { alignItems: 'center', borderColor: colors.asphalt, borderWidth: 1.5, flexDirection: 'row', justifyContent: 'space-between', marginTop: 16, paddingHorizontal: 16, paddingVertical: 15 },
});
