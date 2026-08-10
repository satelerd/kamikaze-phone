import { useCallback, useEffect, useRef, useState } from 'react';
import * as Haptics from 'expo-haptics';
import { DeviceMotion, type DeviceMotionMeasurement } from 'expo-sensors';
import { Platform } from 'react-native';

import { makeSyntheticThrowSamples, MotionDetector } from '../motion/engine';
import { applyAxisCalibration, type AxisCalibration } from '../motion/calibration';
import { buildManualAttempt } from '../motion/manualCapture';
import { normalizeRotationRate } from '../motion/normalize';
import { integrateQuaternion } from '../motion/replay';
import { loadAttemptHistory, saveAttemptHistory } from '../storage/attemptHistory';
import { loadMotionCalibrationProfile, saveMotionCalibrationProfile } from '../storage/motionCalibration';
import type { DetectedAttempt, DetectorSnapshot, MotionSample, Quaternion } from '../motion/types';

type SensorStatus = 'checking' | 'ready' | 'denied' | 'unavailable' | 'error';

type LivePoint = {
  accelG: number;
  gyroDps: number;
};

const initialSnapshot: DetectorSnapshot = {
  phase: 'idle',
  accelG: 1,
  gyroDps: 0,
  actualHz: 0,
  rotationDegrees: { x: 0, y: 0, z: 0, total: 0 },
  sampleCount: 0,
  lastAttempt: null,
};

function normalizeMeasurement(measurement: DeviceMotionMeasurement): MotionSample {
  return {
    timestampS: measurement.accelerationIncludingGravity.timestamp,
    accelerationIncludingGravity: {
      x: measurement.accelerationIncludingGravity.x,
      y: measurement.accelerationIncludingGravity.y,
      z: measurement.accelerationIncludingGravity.z,
    },
    rotationRateDps: normalizeRotationRate(measurement.rotationRate, Platform.OS),
  };
}

export function useMotionLab() {
  const detectorRef = useRef(new MotionDetector());
  const subscriptionRef = useRef<{ remove: () => void } | null>(null);
  const lastPaintAtRef = useRef(0);
  const lastPosePaintAtRef = useRef(0);
  const livePoseQuaternionRef = useRef<Quaternion>({ w: 1, x: 0, y: 0, z: 0 });
  const livePoseTimestampRef = useRef<number | null>(null);
  const calibrationSamplesRef = useRef<MotionSample[] | null>(null);
  const manualSamplesRef = useRef<MotionSample[] | null>(null);
  const lastPhaseRef = useRef(initialSnapshot.phase);
  const completedAttemptRef = useRef<string | null>(null);
  const historyRef = useRef<LivePoint[]>([]);
  const attemptsRef = useRef<DetectedAttempt[]>([]);
  const calibrationProfileRef = useRef<AxisCalibration[] | null>(null);

  const [snapshot, setSnapshot] = useState(initialSnapshot);
  const [sensorStatus, setSensorStatus] = useState<SensorStatus>('checking');
  const [history, setHistory] = useState<LivePoint[]>([]);
  const [attempts, setAttempts] = useState<DetectedAttempt[]>([]);
  const [historyReady, setHistoryReady] = useState(false);
  const [liveQuaternion, setLiveQuaternion] = useState<Quaternion>({ w: 1, x: 0, y: 0, z: 0 });
  const [manualRecording, setManualRecording] = useState(false);
  const [manualElapsedMs, setManualElapsedMs] = useState(0);
  const [calibrationProfile, setCalibrationProfile] = useState<AxisCalibration[] | null>(null);

  useEffect(() => {
    loadAttemptHistory().then((storedAttempts) => {
      attemptsRef.current = storedAttempts;
      setAttempts(storedAttempts);
      setHistoryReady(true);
    });
  }, []);

  useEffect(() => {
    loadMotionCalibrationProfile().then((profile) => {
      calibrationProfileRef.current = profile;
      setCalibrationProfile(profile);
    });
  }, []);

  const storeAttempt = useCallback((attempt: DetectedAttempt) => {
    completedAttemptRef.current = attempt.id;
    const updatedAttempts = [
      attempt,
      ...attemptsRef.current.filter((existing) => existing.id !== attempt.id),
    ].slice(0, 50);
    attemptsRef.current = updatedAttempts;
    setAttempts(updatedAttempts);
    saveAttemptHistory(updatedAttempts).catch(() => undefined);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => undefined);
  }, []);

  const publish = useCallback((next: DetectorSnapshot, force = false) => {
    const now = Date.now();
    const phaseChanged = next.phase !== lastPhaseRef.current;
    if (force || phaseChanged || now - lastPaintAtRef.current >= 50) {
      lastPaintAtRef.current = now;
      lastPhaseRef.current = next.phase;
      setSnapshot(next);
      setHistory([...historyRef.current]);
    }

    if (
      next.phase === 'complete' &&
      next.lastAttempt &&
      completedAttemptRef.current !== next.lastAttempt.id
    ) {
      storeAttempt(next.lastAttempt);
    }
  }, [storeAttempt]);

  const handleSample = useCallback((sample: MotionSample) => {
    const next = detectorRef.current.process(sample);
    historyRef.current = [
      ...historyRef.current.slice(-27),
      { accelG: next.accelG, gyroDps: next.gyroDps },
    ];
    publish(next);
  }, [publish]);

  const connect = useCallback(async (askPermission: boolean) => {
    try {
      const available = await DeviceMotion.isAvailableAsync();
      if (!available) {
        setSensorStatus('unavailable');
        return false;
      }

      const permission = askPermission
        ? await DeviceMotion.requestPermissionsAsync()
        : await DeviceMotion.getPermissionsAsync();

      if (!permission.granted) {
        setSensorStatus(permission.canAskAgain ? 'checking' : 'denied');
        return false;
      }

      if (!subscriptionRef.current) {
        DeviceMotion.setUpdateInterval(10);
        subscriptionRef.current = DeviceMotion.addListener((measurement) => {
          const rawSample = normalizeMeasurement(measurement);
          calibrationSamplesRef.current?.push(rawSample);
          const sample = {
            ...rawSample,
            rotationRateDps: applyAxisCalibration(rawSample.rotationRateDps, calibrationProfileRef.current),
          };
          const previousTimestamp = livePoseTimestampRef.current;
          if (previousTimestamp !== null) {
            const dtS = Math.min(0.05, Math.max(0, sample.timestampS - previousTimestamp));
            livePoseQuaternionRef.current = integrateQuaternion(
              livePoseQuaternionRef.current,
              sample.rotationRateDps,
              dtS,
            );
          }
          livePoseTimestampRef.current = sample.timestampS;
          manualSamplesRef.current?.push(sample);

          const now = Date.now();
          if (now - lastPosePaintAtRef.current >= 33) {
            lastPosePaintAtRef.current = now;
            setLiveQuaternion({ ...livePoseQuaternionRef.current });
            const manualSamples = manualSamplesRef.current;
            if (manualSamples && manualSamples.length > 1) {
              setManualElapsedMs(
                (manualSamples.at(-1)!.timestampS - manualSamples[0].timestampS) * 1000,
              );
            }
          }
          handleSample(sample);
        });
      }
      setSensorStatus('ready');
      return true;
    } catch {
      setSensorStatus('error');
      return false;
    }
  }, [handleSample]);

  useEffect(() => {
    connect(false).catch(() => setSensorStatus('error'));
    return () => {
      subscriptionRef.current?.remove();
      subscriptionRef.current = null;
    };
  }, [connect]);

  const arm = useCallback(async () => {
    const connected = sensorStatus === 'ready' || await connect(true);
    if (!connected) return false;

    completedAttemptRef.current = null;
    historyRef.current = [];
    publish(detectorRef.current.arm('sensor'), true);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Rigid).catch(() => undefined);
    return true;
  }, [connect, publish, sensorStatus]);

  const disarm = useCallback(() => {
    publish(detectorRef.current.disarm(), true);
  }, [publish]);

  const simulate = useCallback(() => {
    completedAttemptRef.current = null;
    historyRef.current = [];
    detectorRef.current.arm('synthetic');
    const samples = makeSyntheticThrowSamples();
    samples.forEach(handleSample);
    publish(detectorRef.current.process({
      ...samples[samples.length - 1],
      timestampS: samples[samples.length - 1].timestampS + 0.01,
    }), true);
  }, [handleSample, publish]);

  const startCalibrationCapture = useCallback(() => {
    calibrationSamplesRef.current = [];
  }, []);

  const stopCalibrationCapture = useCallback((): MotionSample[] => {
    const samples = calibrationSamplesRef.current ?? [];
    calibrationSamplesRef.current = null;
    return [...samples];
  }, []);

  const startManualCapture = useCallback(async () => {
    const connected = sensorStatus === 'ready' || await connect(true);
    if (!connected) return false;
    publish(detectorRef.current.disarm(), true);
    manualSamplesRef.current = [];
    setManualElapsedMs(0);
    setManualRecording(true);
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Rigid).catch(() => undefined);
    return true;
  }, [connect, publish, sensorStatus]);

  const stopManualCapture = useCallback((): DetectedAttempt | null => {
    const samples = manualSamplesRef.current ?? [];
    manualSamplesRef.current = null;
    setManualRecording(false);
    const attempt = buildManualAttempt(samples);
    if (attempt) {
      storeAttempt(attempt);
      setSnapshot((current) => ({
        ...current,
        lastAttempt: attempt,
        phase: 'complete',
        rotationDegrees: { ...attempt.rotationDegrees },
        sampleCount: attempt.sampleCount,
      }));
    }
    return attempt;
  }, [storeAttempt]);

  const cancelManualCapture = useCallback(() => {
    manualSamplesRef.current = null;
    setManualRecording(false);
    setManualElapsedMs(0);
  }, []);

  const applyCalibrationProfile = useCallback((profile: AxisCalibration[]) => {
    calibrationProfileRef.current = profile;
    setCalibrationProfile(profile);
    livePoseQuaternionRef.current = { w: 1, x: 0, y: 0, z: 0 };
    livePoseTimestampRef.current = null;
    setLiveQuaternion({ w: 1, x: 0, y: 0, z: 0 });
    saveMotionCalibrationProfile(profile).catch(() => undefined);
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => undefined);
  }, []);

  return {
    snapshot,
    sensorStatus,
    history,
    attempts,
    historyReady,
    liveQuaternion,
    manualElapsedMs,
    manualRecording,
    calibrationProfile,
    arm,
    disarm,
    simulate,
    startCalibrationCapture,
    startManualCapture,
    stopCalibrationCapture,
    stopManualCapture,
    cancelManualCapture,
    applyCalibrationProfile,
    requestPermission: () => connect(true),
  };
}
