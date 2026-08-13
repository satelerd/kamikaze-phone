// Arm/disarm a ThrowTracker on the live IMU stream. One throw per arm:
// the tracker disarms itself the moment a complete record lands, so a
// double-bounce never scores twice in a round.
import { useCallback, useEffect, useRef } from 'react';
import { FXEngine } from '@/lib/fx';
import { ThrowTracker } from '@/lib/physics';
import type { ThrowRecord } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';

export function useThrowCapture(
  onRecord: (rec: ThrowRecord) => void,
): { arm: () => void; disarm: () => void } {
  const unsubRef = useRef<(() => void) | null>(null);
  const cbRef = useRef(onRecord);
  cbRef.current = onRecord;

  const disarm = useCallback(() => {
    unsubRef.current?.();
    unsubRef.current = null;
  }, []);

  const arm = useCallback(() => {
    disarm();
    const tracker = new ThrowTracker(
      (rec) => {
        disarm();
        cbRef.current(rec);
      },
      (e) => FXEngine.handle(e),
    );
    unsubRef.current = SensorEngine.get().onIMU((s) => tracker.feed(s));
  }, [disarm]);

  useEffect(() => disarm, [disarm]);
  return { arm, disarm };
}
