// AudioBus: music / sfx / voice channels over WebAudio.
// Loads generated ElevenLabs assets from /audio/manifest.json when present;
// every named sound also has a procedural fallback so the game is fully
// playable with zero downloaded assets.
import { getState, subscribe } from './store';

export type SoundName =
  | 'tick' | 'tick-fast' | 'flip' | 'launch' | 'catch' | 'slam' | 'bail'
  | 'grind-loop' | 'whoosh' | 'fanfare' | 'achievement' | 'select' | 'start'
  | 'potato-tick' | 'potato-boom' | 'crowd-oooh';

interface Manifest {
  music: Record<string, string>;
  sfx: Partial<Record<SoundName, string>>;
}

class AudioBusImpl {
  private ctx: AudioContext | null = null;
  private musicGain: GainNode | null = null;
  private sfxGain: GainNode | null = null;
  private buffers = new Map<string, AudioBuffer>();
  private manifest: Manifest | null = null;
  private musicSource: AudioBufferSourceNode | null = null;
  private loops = new Map<string, { src: AudioBufferSourceNode | OscillatorNode; gain: GainNode }>();

  /** Must be called from a user gesture (audio unlock). */
  ensure(): AudioContext | null {
    if (typeof window === 'undefined') return null;
    if (!this.ctx) {
      const AC = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!AC) return null;
      this.ctx = new AC();
      this.musicGain = this.ctx.createGain();
      this.sfxGain = this.ctx.createGain();
      this.musicGain.connect(this.ctx.destination);
      this.sfxGain.connect(this.ctx.destination);
      this.applySettings();
      subscribe(() => this.applySettings());
      void this.loadManifest();
    }
    if (this.ctx.state === 'suspended') void this.ctx.resume();
    return this.ctx;
  }

  private applySettings(): void {
    const { settings } = getState();
    if (this.musicGain) this.musicGain.gain.value = settings.muted ? 0 : settings.musicVolume;
    if (this.sfxGain) this.sfxGain.gain.value = settings.muted ? 0 : settings.sfxVolume;
  }

  private async loadManifest(): Promise<void> {
    try {
      const res = await fetch('/audio/manifest.json');
      if (res.ok) this.manifest = (await res.json()) as Manifest;
    } catch {
      this.manifest = null;
    }
  }

  private async buffer(url: string): Promise<AudioBuffer | null> {
    if (this.buffers.has(url)) return this.buffers.get(url)!;
    if (!this.ctx) return null;
    try {
      const res = await fetch(url);
      const buf = await this.ctx.decodeAudioData(await res.arrayBuffer());
      this.buffers.set(url, buf);
      return buf;
    } catch {
      return null;
    }
  }

  async play(name: SoundName): Promise<void> {
    const ctx = this.ensure();
    if (!ctx || !this.sfxGain) return;
    const url = this.manifest?.sfx?.[name];
    if (url) {
      const buf = await this.buffer(url);
      if (buf) {
        const src = ctx.createBufferSource();
        src.buffer = buf;
        src.connect(this.sfxGain);
        src.start();
        return;
      }
    }
    this.synth(name, ctx, this.sfxGain);
  }

  startLoop(name: SoundName): void {
    const ctx = this.ensure();
    if (!ctx || !this.sfxGain || this.loops.has(name)) return;
    const gain = ctx.createGain();
    gain.gain.value = 0.5;
    gain.connect(this.sfxGain);
    // procedural grind: filtered noise
    const bufferSize = ctx.sampleRate * 1;
    const noiseBuf = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
    const data = noiseBuf.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) data[i] = Math.random() * 2 - 1;
    const src = ctx.createBufferSource();
    src.buffer = noiseBuf;
    src.loop = true;
    const filter = ctx.createBiquadFilter();
    filter.type = 'bandpass';
    filter.frequency.value = name === 'grind-loop' ? 900 : 300;
    src.connect(filter);
    filter.connect(gain);
    src.start();
    this.loops.set(name, { src, gain });
  }

  setLoopIntensity(name: SoundName, v: number): void {
    const loop = this.loops.get(name);
    if (loop) loop.gain.gain.value = Math.max(0, Math.min(1, v));
  }

  stopLoop(name: SoundName): void {
    const loop = this.loops.get(name);
    if (!loop) return;
    try { loop.src.stop(); } catch { /* already stopped */ }
    this.loops.delete(name);
  }

  async playMusic(trackId = 'main'): Promise<void> {
    const ctx = this.ensure();
    if (!ctx || !this.musicGain) return;
    await this.loadManifest();
    const url = this.manifest?.music?.[trackId];
    if (!url) return; // no generated soundtrack yet: silence, not noise
    const buf = await this.buffer(url);
    if (!buf) return;
    this.stopMusic();
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.loop = true;
    src.connect(this.musicGain);
    src.start();
    this.musicSource = src;
  }

  stopMusic(): void {
    try { this.musicSource?.stop(); } catch { /* noop */ }
    this.musicSource = null;
  }

  /** Duck music while the narrator talks. */
  duck(on: boolean): void {
    if (!this.ctx || !this.musicGain) return;
    const { settings } = getState();
    const target = settings.muted ? 0 : settings.musicVolume * (on ? 0.25 : 1);
    this.musicGain.gain.linearRampToValueAtTime(target, this.ctx.currentTime + 0.25);
  }

  // ------------------------------------------------------------------
  // Procedural fallbacks (WebAudio synthesis; no assets required)
  // ------------------------------------------------------------------
  private synth(name: SoundName, ctx: AudioContext, out: GainNode): void {
    const now = ctx.currentTime;
    const env = (g: GainNode, a: number, d: number, peak = 0.8) => {
      g.gain.setValueAtTime(0, now);
      g.gain.linearRampToValueAtTime(peak, now + a);
      g.gain.exponentialRampToValueAtTime(0.001, now + a + d);
    };
    const osc = (type: OscillatorType, f0: number, f1: number, dur: number, peak = 0.8) => {
      const o = ctx.createOscillator();
      const g = ctx.createGain();
      o.type = type;
      o.frequency.setValueAtTime(f0, now);
      o.frequency.exponentialRampToValueAtTime(Math.max(1, f1), now + dur);
      env(g, 0.005, dur, peak);
      o.connect(g); g.connect(out);
      o.start(now); o.stop(now + dur + 0.1);
    };
    const noise = (dur: number, freq: number, peak = 0.8) => {
      const buf = ctx.createBuffer(1, ctx.sampleRate * dur, ctx.sampleRate);
      const d = buf.getChannelData(0);
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      const src = ctx.createBufferSource();
      src.buffer = buf;
      const f = ctx.createBiquadFilter();
      f.type = 'lowpass'; f.frequency.value = freq;
      const g = ctx.createGain();
      env(g, 0.002, dur, peak);
      src.connect(f); f.connect(g); g.connect(out);
      src.start(now);
    };
    switch (name) {
      case 'tick': case 'potato-tick': osc('square', 1200, 900, 0.05, 0.35); break;
      case 'tick-fast': osc('square', 1600, 1200, 0.04, 0.4); break;
      case 'flip': osc('sine', 500, 1400, 0.12, 0.5); break;
      case 'launch': case 'whoosh': noise(0.35, 2500, 0.5); break;
      case 'catch': osc('sine', 300, 80, 0.2, 0.7); noise(0.12, 1200, 0.4); break;
      case 'slam': case 'potato-boom': noise(0.5, 400, 0.9); osc('sine', 120, 40, 0.4, 0.8); break;
      case 'bail': case 'crowd-oooh': osc('sawtooth', 400, 60, 0.6, 0.5); break;
      case 'fanfare': case 'achievement': {
        [523, 659, 784, 1047].forEach((f, i) => {
          const o = ctx.createOscillator(); const g = ctx.createGain();
          o.type = 'triangle'; o.frequency.value = f;
          g.gain.setValueAtTime(0, now + i * 0.09);
          g.gain.linearRampToValueAtTime(0.4, now + i * 0.09 + 0.02);
          g.gain.exponentialRampToValueAtTime(0.001, now + i * 0.09 + 0.35);
          o.connect(g); g.connect(out);
          o.start(now + i * 0.09); o.stop(now + i * 0.09 + 0.4);
        });
        break;
      }
      case 'select': osc('sine', 700, 900, 0.06, 0.3); break;
      case 'start': osc('sine', 400, 800, 0.18, 0.5); break;
      case 'grind-loop': noise(0.4, 900, 0.5); break;
      default: osc('sine', 600, 600, 0.08, 0.3);
    }
  }
}

export const AudioBus = new AudioBusImpl();
