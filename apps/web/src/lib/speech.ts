// Narration helper: routes lines to the best available voice.
// Priority: live ElevenLabs narrator agent > pre-generated clips > speechSynthesis.
// speechSynthesis works on both iOS Safari and Android Chrome, so narration
// (hot-potato names, fallback commentary) never goes silent.
import { AudioBus } from './audio';
import { getState } from './store';

type AgentSpeaker = (text: string) => boolean;

let agentSpeaker: AgentSpeaker | null = null;

/** The narrator agent registers itself here when connected. */
export function registerAgentSpeaker(fn: AgentSpeaker | null): void {
  agentSpeaker = fn;
}

function pickVoice(): SpeechSynthesisVoice | null {
  if (typeof window === 'undefined' || !window.speechSynthesis) return null;
  const voices = window.speechSynthesis.getVoices();
  return (
    voices.find((v) => v.lang.startsWith('en-US') && /male|fred|alex|daniel/i.test(v.name)) ??
    voices.find((v) => v.lang.startsWith('en-US')) ??
    voices.find((v) => v.lang.startsWith('en')) ??
    voices[0] ??
    null
  );
}

export interface SpeakOpts {
  /** surfer = slower + lower; caller = crisp */
  style?: 'surfer' | 'caller';
  /** skip the live agent and force local TTS (e.g. hot-potato names) */
  forceLocal?: boolean;
  interrupt?: boolean;
}

export function speak(text: string, opts: SpeakOpts = {}): void {
  const { settings } = getState();
  if (settings.muted) return;
  if (!opts.forceLocal && settings.narratorEnabled && agentSpeaker?.(text)) return;

  if (typeof window === 'undefined' || !window.speechSynthesis) return;
  if (opts.interrupt) window.speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text);
  const voice = pickVoice();
  if (voice) u.voice = voice;
  if (opts.style === 'surfer') {
    u.rate = 0.95;
    u.pitch = 0.85;
  } else {
    u.rate = 1.05;
    u.pitch = 1.0;
  }
  AudioBus.duck(true);
  u.onend = () => AudioBus.duck(false);
  window.speechSynthesis.speak(u);
}

export function stopSpeaking(): void {
  if (typeof window !== 'undefined' && window.speechSynthesis) window.speechSynthesis.cancel();
  AudioBus.duck(false);
}
