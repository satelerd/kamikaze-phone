import { DEFAULT_GAME_PREFERENCES, loadGamePreferences } from '../game/gameProfile';
import type { ExportSnapshot } from '../export/exportBundle';
import { loadAttemptHistory } from './attemptHistory';
import { loadCalibrationCaptures } from './calibrationHistory';
import { loadCameraPreset } from './cameraPreset';
import { loadMotionCalibrationProfile } from './motionCalibration';
import { loadCustomTricks, loadGripHand } from './trickCatalog';
import { loadTrickCalibrations } from './trickCalibrationHistory';

export async function loadExportSnapshot(): Promise<ExportSnapshot> {
  const [
    attempts,
    calibrationCaptures,
    cameraPreset,
    gamePreferences,
    gripHand,
    motionCalibrationProfile,
    customTricks,
    trickCalibrations,
  ] = await Promise.all([
    loadAttemptHistory(),
    loadCalibrationCaptures(),
    loadCameraPreset(),
    loadGamePreferences(),
    loadGripHand(),
    loadMotionCalibrationProfile(),
    loadCustomTricks(),
    loadTrickCalibrations(),
  ]);

  return {
    attempts,
    calibrationCaptures,
    customTricks,
    settings: {
      cameraPreset,
      gamePreferences: gamePreferences ?? DEFAULT_GAME_PREFERENCES,
      gripHand,
      motionCalibrationProfile,
    },
    trickCalibrations,
  };
}
