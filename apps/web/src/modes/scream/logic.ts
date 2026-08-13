// Scream Meter logic: getUserMedia + AnalyserNode RMS metering, hype-scream
// multiplier mapping, and whoosh detection thresholds. The page owns the flow.
export interface MicLevel {
  /** 0..1 RMS of the time-domain signal */
  rms: number;
  /** dBFS-ish: 20*log10(rms), clamped at -80 */
  db: number;
}

export const SCREAM_CFG = {
  hypeWindowMs: 3000,
  /** db → multiplier mapping: quietDb maps to 1.0x, loudDb to 2.0x */
  quietDb: -35,
  loudDb: -5,
  /** whoosh: flight peak must beat both the absolute floor and idle * factor */
  whooshFloorRms: 0.06,
  whooshIdleFactor: 2.5,
  whooshBonus: 8,
  /** instant narrator reaction while screaming */
  instantReactRms: 0.55,
  bansheeMultiplier: 1.95,
};

export function rmsToDb(rms: number): number {
  return Math.max(-80, 20 * Math.log10(Math.max(rms, 1e-4)));
}

/** 1.0x..2.0x from the peak dB of the hype window. */
export function multiplierFromDb(peakDb: number): number {
  const span = SCREAM_CFG.loudDb - SCREAM_CFG.quietDb;
  const k = Math.max(0, Math.min(1, (peakDb - SCREAM_CFG.quietDb) / span));
  return 1 + k;
}

export function screamLine(mult: number): string {
  if (mult >= SCREAM_CFG.bansheeMultiplier) return 'BANSHEE ALERT! The whole beach heard that one!';
  if (mult >= 1.6) return 'Gnarly lungs, dude! That scream had serious wattage!';
  if (mult >= 1.3) return 'Decent hype, but I know you have more in the tank!';
  return 'That was a library whisper. Scream like you mean it!';
}

/**
 * Microphone RMS meter over an AnalyserNode. start() must be called from a
 * user gesture; stop() releases the mic tracks and closes the context.
 */
export class MicMeter {
  running = false;
  private ctx: AudioContext | null = null;
  private analyser: AnalyserNode | null = null;
  private stream: MediaStream | null = null;
  private raf = 0;
  private buf: Uint8Array | null = null;
  private onLevel: (lv: MicLevel) => void;

  constructor(onLevel: (lv: MicLevel) => void) {
    this.onLevel = onLevel;
  }

  async start(): Promise<boolean> {
    if (this.running) return true;
    if (typeof navigator === 'undefined' || !navigator.mediaDevices) return false;
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
      });
    } catch {
      return false;
    }
    const AC =
      window.AudioContext ??
      (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!AC) {
      this.stopTracks();
      return false;
    }
    this.ctx = new AC();
    const src = this.ctx.createMediaStreamSource(this.stream);
    this.analyser = this.ctx.createAnalyser();
    this.analyser.fftSize = 1024;
    src.connect(this.analyser);
    this.buf = new Uint8Array(this.analyser.fftSize);
    this.running = true;
    const loop = () => {
      if (!this.running || !this.analyser || !this.buf) return;
      this.analyser.getByteTimeDomainData(this.buf);
      let sum = 0;
      for (let i = 0; i < this.buf.length; i++) {
        const v = (this.buf[i] - 128) / 128;
        sum += v * v;
      }
      const rms = Math.sqrt(sum / this.buf.length);
      this.onLevel({ rms, db: rmsToDb(rms) });
      this.raf = requestAnimationFrame(loop);
    };
    this.raf = requestAnimationFrame(loop);
    return true;
  }

  /** Releases the microphone. Always call on unmount. */
  stop(): void {
    this.running = false;
    if (this.raf) cancelAnimationFrame(this.raf);
    this.raf = 0;
    this.stopTracks();
    void this.ctx?.close().catch(() => {});
    this.ctx = null;
    this.analyser = null;
    this.buf = null;
  }

  private stopTracks(): void {
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
  }
}
