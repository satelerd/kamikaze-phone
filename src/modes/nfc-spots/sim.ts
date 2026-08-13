// Desktop simulator for NFC Spots: fake tag serials plus an IMU throw so the
// stomp flow (land, then re-scan the tag) can be exercised without hardware.
import { generateThrow } from '@/lib/sim';
import type { IMUSample } from '@/lib/types';

const SIM_SERIALS = ['sim:04:20:69:aa', 'sim:04:20:69:bb', 'sim:04:20:69:cc'];
let simIndex = 0;

/** Cycles through a small pool of fake tag serials. */
export function nextSimSerial(): string {
  const s = SIM_SERIALS[simIndex % SIM_SERIALS.length];
  simIndex += 1;
  return s;
}

/** A quick IMU throw so the page registers a landing. Returns cancel(). */
export function simulateStompThrow(
  feedIMU: (s: IMUSample) => void,
  done?: () => void,
): () => void {
  const samples = generateThrow({ airtime: 0.6, spinsX: 1, leadInMs: 500 });
  const start = performance.now();
  let i = 0;
  const iv = setInterval(() => {
    const now = performance.now() - start;
    while (i < samples.length && samples[i].t <= now) feedIMU(samples[i++]);
    if (i >= samples.length) {
      clearInterval(iv);
      done?.();
    }
  }, 16);
  return () => clearInterval(iv);
}
