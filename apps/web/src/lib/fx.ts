// FX engine: torch + vibration + screen-flash + SFX, driven by game events.
// Torch: MediaStreamTrack.applyConstraints({advanced:[{torch}]}) (Android Chrome).
// Vibration: navigator.vibrate (Android). iOS web gets screen-flash + audio
// transients instead: same beat, different hardware.
import { AudioBus } from './audio';
import { getState } from './store';
import type { GameEvent } from './types';

type FlashListener = (on: boolean) => void;

class FXEngineImpl {
  private torchTrack: MediaStreamTrack | null = null;
  private torchOn = false;
  private flashListeners = new Set<FlashListener>();
  private grindActive = false;
  private grindFlicker: ReturnType<typeof setInterval> | null = null;

  /** The app shell renders a white overlay driven by this (torch fallback). */
  onScreenFlash(cb: FlashListener): () => void {
    this.flashListeners.add(cb);
    return () => this.flashListeners.delete(cb);
  }

  /** Acquire the rear camera torch. Call from a user gesture. */
  async enableTorch(): Promise<boolean> {
    if (this.torchTrack) return true;
    if (!getState().settings.torchEnabled) return false;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
      const track = stream.getVideoTracks()[0];
      const caps = track.getCapabilities ? (track.getCapabilities() as { torch?: boolean }) : {};
      if (!caps.torch) {
        track.stop();
        return false;
      }
      this.torchTrack = track;
      return true;
    } catch {
      return false;
    }
  }

  releaseTorch(): void {
    this.torchTrack?.stop();
    this.torchTrack = null;
    this.torchOn = false;
  }

  private async setTorch(on: boolean): Promise<void> {
    if (this.torchTrack) {
      if (this.torchOn === on) return;
      this.torchOn = on;
      try {
        await this.torchTrack.applyConstraints({ advanced: [{ torch: on } as MediaTrackConstraintSet] });
        return;
      } catch {
        // fall through to screen flash
      }
    }
    this.flashListeners.forEach((cb) => cb(on));
  }

  private vibrate(pattern: number | number[]): void {
    if (!getState().settings.hapticsEnabled) return;
    if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
      try { navigator.vibrate(pattern); } catch { /* unsupported */ }
    }
  }

  private pulse(ms: number): void {
    void this.setTorch(true);
    setTimeout(() => void this.setTorch(false), ms);
  }

  /** Single entry point: every game event becomes light + buzz + sound. */
  handle(e: GameEvent): void {
    switch (e.type) {
      case 'countdown-tick':
        void AudioBus.play(e.n <= 3 ? 'tick-fast' : 'tick');
        this.vibrate(20);
        if (e.n <= 3) this.pulse(40);
        break;
      case 'launch':
        void AudioBus.play('launch');
        break;
      case 'flip':
        void AudioBus.play('flip');
        this.vibrate(25);
        this.pulse(35);
        break;
      case 'catch':
        void AudioBus.play(e.clean ? 'catch' : 'slam');
        this.vibrate(e.clean ? [80, 40, 120] : 250);
        this.pulse(e.clean ? 120 : 300);
        break;
      case 'bail':
        void AudioBus.play('bail');
        this.vibrate([300, 100, 300]);
        break;
      case 'grind-start':
        if (this.grindActive) break;
        this.grindActive = true;
        AudioBus.startLoop('grind-loop');
        this.grindFlicker = setInterval(() => {
          if (Math.random() < 0.6) this.pulse(25);
          this.vibrate(15);
        }, 90);
        break;
      case 'grind-tick':
        AudioBus.setLoopIntensity('grind-loop', e.intensity);
        break;
      case 'grind-end':
        this.grindActive = false;
        if (this.grindFlicker) clearInterval(this.grindFlicker);
        this.grindFlicker = null;
        AudioBus.stopLoop('grind-loop');
        void AudioBus.play('catch');
        this.vibrate([60, 30, 60]);
        break;
      case 'trick':
        if (e.result.grade === 'S') void AudioBus.play('fanfare');
        break;
      case 'achievement':
        void AudioBus.play('achievement');
        this.vibrate([50, 50, 50, 50, 150]);
        this.pulse(200);
        break;
      case 'ui-select':
        void AudioBus.play('select');
        this.vibrate(10);
        break;
      case 'ui-start':
        void AudioBus.play('start');
        this.vibrate(30);
        break;
      case 'peak':
        break;
    }
  }
}

export const FXEngine = new FXEngineImpl();
