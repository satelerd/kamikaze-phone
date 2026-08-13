// Unified sensor engine: one stream for iOS Safari and Android Chrome,
// plus optional Generic Sensor API streams and a simulator injector.
import type { IMUSample, LuxSample, MagSample } from './types';

type Listener<T> = (s: T) => void;

const BUFFER_SIZE = 8192;

declare global {
  interface Window {
    Magnetometer?: new (opts?: { frequency?: number }) => GenericSensor;
    AmbientLightSensor?: new (opts?: { frequency?: number }) => GenericSensor;
  }
}

interface GenericSensor {
  start(): void;
  stop(): void;
  addEventListener(type: 'reading' | 'error', cb: (e: Event) => void): void;
  x?: number;
  y?: number;
  z?: number;
  illuminance?: number;
}

export class SensorEngine {
  private static _instance: SensorEngine | null = null;
  static get(): SensorEngine {
    if (!this._instance) this._instance = new SensorEngine();
    return this._instance;
  }

  private t0 = 0;
  private buffer: IMUSample[] = [];
  private imuListeners = new Set<Listener<IMUSample>>();
  private magListeners = new Set<Listener<MagSample>>();
  private luxListeners = new Set<Listener<LuxSample>>();
  private motionHandler: ((e: DeviceMotionEvent) => void) | null = null;
  private magSensor: GenericSensor | null = null;
  private luxSensor: GenericSensor | null = null;
  running = false;
  simulated = false;

  /** iOS requires a user-gesture permission request; Android resolves 'granted'. */
  async requestPermission(): Promise<boolean> {
    const DME = DeviceMotionEvent as unknown as { requestPermission?: () => Promise<string> };
    if (typeof DME.requestPermission === 'function') {
      try {
        return (await DME.requestPermission()) === 'granted';
      } catch {
        return false;
      }
    }
    return typeof window !== 'undefined' && 'DeviceMotionEvent' in window;
  }

  start(): void {
    if (this.running || typeof window === 'undefined') return;
    this.running = true;
    this.t0 = performance.now();
    this.buffer = [];

    this.motionHandler = (e: DeviceMotionEvent) => {
      const g = e.accelerationIncludingGravity;
      const l = e.acceleration;
      const r = e.rotationRate;
      this.push({
        t: performance.now() - this.t0,
        ax: g?.x ?? 0, ay: g?.y ?? 0, az: g?.z ?? 0,
        lx: l?.x ?? 0, ly: l?.y ?? 0, lz: l?.z ?? 0,
        rx: r?.beta ?? 0, ry: r?.gamma ?? 0, rz: r?.alpha ?? 0,
      });
    };
    window.addEventListener('devicemotion', this.motionHandler);
    this.startMagnetometer();
    this.startAmbientLight();
  }

  stop(): void {
    if (!this.running) return;
    this.running = false;
    if (this.motionHandler) window.removeEventListener('devicemotion', this.motionHandler);
    this.motionHandler = null;
    this.magSensor?.stop();
    this.magSensor = null;
    this.luxSensor?.stop();
    this.luxSensor = null;
  }

  private startMagnetometer(): void {
    if (!window.Magnetometer) return;
    try {
      const s = new window.Magnetometer({ frequency: 30 });
      s.addEventListener('reading', () => {
        const { x = 0, y = 0, z = 0 } = s;
        const sample: MagSample = {
          t: performance.now() - this.t0,
          x, y, z,
          mag: Math.hypot(x, y, z),
        };
        this.magListeners.forEach((cb) => cb(sample));
      });
      s.addEventListener('error', () => s.stop());
      s.start();
      this.magSensor = s;
    } catch {
      this.magSensor = null;
    }
  }

  private startAmbientLight(): void {
    if (!window.AmbientLightSensor) return;
    try {
      const s = new window.AmbientLightSensor({ frequency: 10 });
      s.addEventListener('reading', () => {
        const sample: LuxSample = { t: performance.now() - this.t0, lux: s.illuminance ?? 0 };
        this.luxListeners.forEach((cb) => cb(sample));
      });
      s.addEventListener('error', () => s.stop());
      s.start();
      this.luxSensor = s;
    } catch {
      this.luxSensor = null;
    }
  }

  /** Inject synthetic samples (desktop demo, physics verification, replays). */
  injectSamples(samples: IMUSample[], realtime = false): Promise<void> {
    this.simulated = true;
    if (!realtime) {
      samples.forEach((s) => this.push(s));
      return Promise.resolve();
    }
    return new Promise((resolve) => {
      const start = performance.now();
      const step = () => {
        const now = performance.now() - start;
        while (samples.length && samples[0].t <= now) this.push(samples.shift()!);
        if (samples.length) requestAnimationFrame(step);
        else resolve();
      };
      requestAnimationFrame(step);
    });
  }

  private push(s: IMUSample): void {
    this.buffer.push(s);
    if (this.buffer.length > BUFFER_SIZE) this.buffer.splice(0, this.buffer.length - BUFFER_SIZE);
    this.imuListeners.forEach((cb) => cb(s));
  }

  onIMU(cb: Listener<IMUSample>): () => void {
    this.imuListeners.add(cb);
    return () => this.imuListeners.delete(cb);
  }
  onMag(cb: Listener<MagSample>): () => void {
    this.magListeners.add(cb);
    return () => this.magListeners.delete(cb);
  }
  onLux(cb: Listener<LuxSample>): () => void {
    this.luxListeners.add(cb);
    return () => this.luxListeners.delete(cb);
  }

  /** Samples from the last `ms` milliseconds. */
  window(ms: number): IMUSample[] {
    if (!this.buffer.length) return [];
    const cutoff = this.buffer[this.buffer.length - 1].t - ms;
    let i = this.buffer.length - 1;
    while (i > 0 && this.buffer[i - 1].t >= cutoff) i--;
    return this.buffer.slice(i);
  }

  all(): IMUSample[] {
    return this.buffer.slice();
  }
}
