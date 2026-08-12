import { useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { PhoneScene3D } from '../components/PhoneScene3D';
import type { useMotionLab } from '../hooks/useMotionLab';
import {
  analyzeCalibrationCapture,
  summarizeCalibration,
  type CalibrationResult,
  type CalibrationStep,
} from '../motion/calibration';
import { multiplyQuaternion, normalizeQuaternion, quaternionFromEulerDegrees } from '../motion/replay';
import type { Quaternion, ReplayFrame, Vector3 } from '../motion/types';
import { appendCalibrationCapture } from '../storage/calibrationHistory';
import { fonts } from '../theme';
import { GlassSurface } from './GlassSurface';
import { gameColors, gameRadii } from './theme';

type MotionController = ReturnType<typeof useMotionLab>;
type QuickPhase = 'demo' | 'countdown' | 'recording' | 'result' | 'done';

const MOVE_WINDOW_MS = 1750;
const HOLD_WINDOW_MS = 420;
const QUICK_CAMERA = { azimuth: 0, elevation: 0, distance: 4.5 };
const QUICK_STEPS: Array<CalibrationStep & { instruction: string; name: string }> = [
  { axis: 'x', degrees: 90, direction: 1, id: 'quick-x-plus-90', instruction: 'Tip the top edge away from you.', name: 'PITCH FORWARD', tempo: 'slow' },
  { axis: 'y', degrees: 90, direction: 1, id: 'quick-y-plus-90', instruction: 'Roll the right edge away from you.', name: 'ROLL RIGHT', tempo: 'slow' },
  { axis: 'z', degrees: 90, direction: 1, id: 'quick-z-plus-90', instruction: 'Turn the screen clockwise like a shuvit.', name: 'TURN RIGHT', tempo: 'slow' },
];

const delay = (milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const clamp = (value: number) => Math.min(1, Math.max(0, value));

function axisVector(step: CalibrationStep, progress: number): Vector3 {
  return {
    x: step.axis === 'x' ? step.degrees * step.direction * progress : 0,
    y: step.axis === 'y' ? step.degrees * step.direction * progress : 0,
    z: step.axis === 'z' ? step.degrees * step.direction * progress : 0,
  };
}

function relativeQuaternion(baseline: Quaternion, current: Quaternion): Quaternion {
  const inverse = { w: baseline.w, x: -baseline.x, y: -baseline.y, z: -baseline.z };
  return normalizeQuaternion(multiplyQuaternion(inverse, current));
}

function QuickButton({ label, onPress, secondary = false }: { label: string; onPress: () => void; secondary?: boolean }) {
  return (
    <Pressable onPress={onPress} style={[styles.button, secondary && styles.buttonSecondary]}>
      <Text style={[styles.buttonText, secondary && styles.buttonTextSecondary]}>{label}</Text>
      <Text style={[styles.buttonArrow, secondary && styles.buttonTextSecondary]}>→</Text>
    </Pressable>
  );
}

export function QuickCalibration({
  motion,
  onClose,
  onOpenFull,
  shellColor,
}: {
  motion: MotionController;
  onClose: () => void;
  onOpenFull: () => void;
  shellColor: string;
}) {
  const [stepIndex, setStepIndex] = useState(0);
  const [phase, setPhase] = useState<QuickPhase>('demo');
  const [countdown, setCountdown] = useState(3);
  const [targetProgress, setTargetProgress] = useState(0);
  const [result, setResult] = useState<CalibrationResult | null>(null);
  const [results, setResults] = useState<CalibrationResult[]>([]);
  const [profileApplied, setProfileApplied] = useState(false);
  const runIdRef = useRef(0);
  const baselineRef = useRef<Quaternion>({ ...motion.liveQuaternion });
  const step = QUICK_STEPS[stepIndex];

  useEffect(() => {
    if (phase !== 'demo') return;
    const timer = setInterval(() => {
      const cycle = Date.now() % 2650;
      setTargetProgress(cycle < MOVE_WINDOW_MS ? cycle / MOVE_WINDOW_MS : cycle < 2250 ? 1 : 0);
    }, 33);
    return () => clearInterval(timer);
  }, [phase, stepIndex]);

  useEffect(() => () => {
    runIdRef.current += 1;
    motion.stopCalibrationCapture();
  }, [motion.stopCalibrationCapture]);

  const actualFrame: ReplayFrame = useMemo(() => ({
    accelG: motion.snapshot.accelG,
    gyroDps: motion.snapshot.gyroDps,
    progress: targetProgress,
    quaternion: relativeQuaternion(baselineRef.current, motion.liveQuaternion),
    timestampMs: targetProgress * MOVE_WINDOW_MS,
  }), [motion.liveQuaternion, motion.snapshot.accelG, motion.snapshot.gyroDps, targetProgress]);
  const targetFrame: ReplayFrame = useMemo(() => ({
    accelG: 1,
    gyroDps: 0,
    progress: targetProgress,
    quaternion: quaternionFromEulerDegrees(axisVector(step, targetProgress)),
    timestampMs: targetProgress * MOVE_WINDOW_MS,
  }), [step, targetProgress]);

  const startStep = async () => {
    const connected = motion.sensorStatus === 'ready' || await motion.requestPermission();
    if (!connected) return;
    const runId = runIdRef.current + 1;
    runIdRef.current = runId;
    baselineRef.current = { ...motion.liveQuaternion };
    setResult(null);
    setTargetProgress(0);
    setPhase('countdown');

    for (const count of [3, 2, 1]) {
      if (runIdRef.current !== runId) return;
      setCountdown(count);
      await delay(520);
    }
    if (runIdRef.current !== runId) return;

    motion.startCalibrationCapture();
    setPhase('recording');
    const startAt = Date.now();
    const progressTimer = setInterval(() => {
      setTargetProgress(clamp((Date.now() - startAt - HOLD_WINDOW_MS) / MOVE_WINDOW_MS));
    }, 33);
    await delay(HOLD_WINDOW_MS + MOVE_WINDOW_MS + 120);
    clearInterval(progressTimer);
    if (runIdRef.current !== runId) return;

    const samples = motion.stopCalibrationCapture();
    const nextResult = analyzeCalibrationCapture(samples, step);
    const capture = {
      id: `${Date.now()}-${step.id}`,
      recordedAtIso: new Date().toISOString(),
      result: nextResult,
      samples,
      step,
    };
    appendCalibrationCapture(capture).catch(() => undefined);
    setResults((existing) => [...existing.filter(({ stepId }) => stepId !== step.id), nextResult]);
    setResult(nextResult);
    setTargetProgress(1);
    setPhase('result');
  };

  const retry = () => {
    runIdRef.current += 1;
    motion.stopCalibrationCapture();
    baselineRef.current = { ...motion.liveQuaternion };
    setResult(null);
    setTargetProgress(0);
    setPhase('demo');
  };

  const next = () => {
    const completeResults = [...results.filter(({ stepId }) => stepId !== result?.stepId), ...(result ? [result] : [])];
    if (stepIndex < QUICK_STEPS.length - 1) {
      baselineRef.current = { ...motion.liveQuaternion };
      setStepIndex((index) => index + 1);
      setResult(null);
      setTargetProgress(0);
      setPhase('demo');
      return;
    }

    const profile = summarizeCalibration(completeResults, QUICK_STEPS);
    const uniqueAxes = new Set(profile.map(({ rawAxis }) => rawAxis)).size === 3;
    const reliable = completeResults.length === 3 && completeResults.every(({ pass }) => pass);
    if (uniqueAxes && reliable) {
      motion.applyCalibrationProfile(profile);
      setProfileApplied(true);
    }
    setPhase('done');
  };

  if (phase === 'done') {
    const average = results.length === 0 ? 0 : Math.round(results.reduce((sum, item) => sum + item.score, 0) / results.length * 100);
    return (
      <View style={styles.shell}>
        <View style={styles.header}><Text style={styles.kicker}>QUICK CAL / COMPLETE</Text><Pressable onPress={onClose}><Text style={styles.close}>DONE</Text></Pressable></View>
        <View style={styles.doneHero}>
          <Text style={styles.doneScore}>{average}</Text>
          <Text style={styles.doneTitle}>{profileApplied ? 'AXES UPDATED.' : 'FULL CAL RECOMMENDED.'}</Text>
          <Text style={styles.doneCopy}>{profileApplied ? 'The new axis map is active in Play and Practice.' : 'One or more movements overlapped. Run the precision workshop before applying a new map.'}</Text>
        </View>
        <QuickButton label="BACK TO PLAY" onPress={onClose} />
        <QuickButton label="OPEN FULL CALIBRATION" onPress={onOpenFull} secondary />
      </View>
    );
  }

  const dominantDegrees = result ? Math.round(result.measuredDegrees[result.dominantAxis]) : 0;
  return (
    <View style={styles.shell}>
      <View style={styles.header}>
        <View><Text style={styles.kicker}>QUICK CAL / {stepIndex + 1} OF {QUICK_STEPS.length}</Text><Text style={styles.title}>{step.name}</Text></View>
        <Pressable onPress={onClose} style={styles.closeButton}><Text style={styles.close}>CLOSE</Text></Pressable>
      </View>
      <Text style={styles.instruction}>{step.instruction} Copy the coral ghost with your phone.</Text>
      <View style={styles.stage}>
        <GlassSurface fallbackColor="rgba(112,126,172,0.08)" fallbackIntensity={56} style={StyleSheet.absoluteFillObject} />
        <PhoneScene3D camera={QUICK_CAMERA} comparisonFrame={targetFrame} frame={actualFrame} restOrientation="screen" shellColor={shellColor} tone="blue" variant="calibration" />
        <View pointerEvents="none" style={styles.legend}>
          <View style={[styles.legendDot, { backgroundColor: shellColor }]} /><Text style={styles.legendText}>YOU</Text>
          <View style={[styles.legendDot, styles.ghostDot]} /><Text style={styles.legendText}>TARGET</Text>
        </View>
        {(phase === 'countdown' || phase === 'recording') && (
          <View pointerEvents="none" style={styles.cue}>
            <Text style={styles.cueText}>{phase === 'countdown' ? countdown : targetProgress <= 0.02 ? 'HOLD' : 'MOVE'}</Text>
          </View>
        )}
      </View>
      {phase === 'result' && result ? (
        <View style={styles.resultCard}>
          <View><Text style={styles.resultLabel}>{result.pass ? 'AXIS MATCH' : 'MAPPING CAPTURED'}</Text><Text style={styles.resultValue}>{result.dominantAxis.toUpperCase()} {dominantDegrees >= 0 ? '+' : ''}{dominantDegrees}°</Text></View>
          <Text style={styles.resultScore}>{Math.round(result.score * 100)}</Text>
        </View>
      ) : (
        <View style={styles.progressTrack}><View style={[styles.progressFill, { width: `${targetProgress * 100}%` }]} /></View>
      )}
      {phase === 'demo' && <QuickButton label={motion.sensorStatus === 'ready' ? 'COPY THIS MOVE' : 'ENABLE MOTION'} onPress={startStep} />}
      {phase === 'result' && result?.pass && <QuickButton label={stepIndex === QUICK_STEPS.length - 1 ? 'APPLY CALIBRATION' : 'NEXT MOVE'} onPress={next} />}
      {phase === 'result' && !result?.pass && <QuickButton label="TRY AGAIN" onPress={retry} />}
      {phase === 'result' && result?.pass && <QuickButton label="TRY AGAIN" onPress={retry} secondary />}
      {phase === 'result' && !result?.pass && <QuickButton label="CONTINUE TO REVIEW" onPress={next} secondary />}
    </View>
  );
}

const styles = StyleSheet.create({
  shell: { flex: 1, paddingBottom: 96, paddingHorizontal: 16, paddingTop: 14 },
  header: { alignItems: 'flex-start', flexDirection: 'row', justifyContent: 'space-between' },
  kicker: { color: gameColors.ion, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 1 },
  title: { color: gameColors.white, fontFamily: fonts.display, fontSize: 34, letterSpacing: -1.4, marginTop: 6 },
  closeButton: { paddingHorizontal: 8, paddingVertical: 6 },
  close: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 8, letterSpacing: 0.8 },
  instruction: { color: gameColors.frost, fontFamily: fonts.body, fontSize: 12, lineHeight: 18, marginBottom: 14, marginTop: 8, maxWidth: 330 },
  stage: { backgroundColor: 'rgba(8,10,14,0.2)', borderRadius: gameRadii.stage, flex: 1, maxHeight: 450, minHeight: 350, overflow: 'hidden', position: 'relative' },
  legend: { alignItems: 'center', flexDirection: 'row', left: 18, position: 'absolute', top: 18 },
  legendDot: { borderRadius: 4, height: 7, width: 7 },
  ghostDot: { backgroundColor: gameColors.hazard, marginLeft: 13, opacity: 0.66 },
  legendText: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 6, letterSpacing: 0.6, marginLeft: 5 },
  cue: { alignItems: 'center', backgroundColor: 'rgba(5,6,9,0.38)', bottom: 0, justifyContent: 'center', left: 0, position: 'absolute', right: 0, top: 0 },
  cueText: { color: gameColors.volt, fontFamily: fonts.display, fontSize: 54, letterSpacing: -2 },
  progressTrack: { backgroundColor: 'rgba(255,255,255,0.12)', borderRadius: 3, height: 5, marginHorizontal: 4, marginTop: 16, overflow: 'hidden' },
  progressFill: { backgroundColor: gameColors.hazard, height: '100%' },
  resultCard: { alignItems: 'center', backgroundColor: 'rgba(255,255,255,0.08)', borderRadius: 18, flexDirection: 'row', justifyContent: 'space-between', marginTop: 14, padding: 14 },
  resultLabel: { color: gameColors.frostMuted, fontFamily: fonts.monoBold, fontSize: 7, letterSpacing: 0.7 },
  resultValue: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 13, marginTop: 4 },
  resultScore: { color: gameColors.volt, fontFamily: fonts.display, fontSize: 30 },
  button: { alignItems: 'center', backgroundColor: gameColors.ion, borderRadius: gameRadii.control, flexDirection: 'row', justifyContent: 'space-between', marginTop: 12, minHeight: 60, paddingHorizontal: 20 },
  buttonSecondary: { backgroundColor: 'rgba(235,238,248,0.10)', borderColor: 'rgba(255,255,255,0.18)', borderWidth: StyleSheet.hairlineWidth },
  buttonText: { color: gameColors.white, fontFamily: fonts.bodyBold, fontSize: 13 },
  buttonTextSecondary: { color: gameColors.frost },
  buttonArrow: { color: gameColors.white, fontFamily: fonts.body, fontSize: 20 },
  doneHero: { flex: 1, justifyContent: 'center', paddingHorizontal: 8 },
  doneScore: { color: gameColors.volt, fontFamily: fonts.display, fontSize: 92, letterSpacing: -5 },
  doneTitle: { color: gameColors.white, fontFamily: fonts.display, fontSize: 32, letterSpacing: -1.4 },
  doneCopy: { color: gameColors.frostMuted, fontFamily: fonts.body, fontSize: 13, lineHeight: 19, marginTop: 10, maxWidth: 330 },
});
