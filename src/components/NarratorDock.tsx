'use client';

// Bodhi Bytes dock: floating surfer narrator, bottom-right on every page.
// Tap the avatar = mute/unmute everything. The small chevron opens a row with
// narrator on/off and, when an ElevenLabs agent id is configured, a "Go live"
// toggle that connects the real voice agent (@elevenlabs/react). While live,
// speak() routes through the agent and trick events stream to it as
// contextual updates; on disconnect everything falls back to scripted lines.
import { useCallback, useEffect, useRef, useState } from 'react';
import { ConversationProvider, useConversation } from '@elevenlabs/react';
import { AudioBus } from '@/lib/audio';
import { Narrator, type NarratorLine } from '@/lib/narrator';
import { registerAgentSpeaker } from '@/lib/speech';
import { getState, subscribe, updateSettings } from '@/lib/store';

const AGENT_ID = process.env.NEXT_PUBLIC_ELEVENLABS_AGENT_ID;

const DOCK_CSS = `
@keyframes kk-bob {
  0%, 100% { transform: translateY(0) rotate(-3deg); }
  50% { transform: translateY(-5px) rotate(3deg); }
}
@keyframes kk-talk {
  0%, 100% { transform: scale(1) rotate(-4deg); }
  25% { transform: scale(1.08) rotate(3deg); }
  50% { transform: scale(1.02) rotate(-2deg); }
  75% { transform: scale(1.1) rotate(4deg); }
}
@keyframes kk-caption-in {
  from { opacity: 0; transform: translateY(6px) scale(0.96); }
  to { opacity: 1; transform: translateY(0) scale(1); }
}
`;

function DockInner() {
  const [muted, setMuted] = useState(false);
  const [narratorOn, setNarratorOn] = useState(true);
  const [caption, setCaption] = useState<NarratorLine | null>(null);
  const [expanded, setExpanded] = useState(false);
  const liveWanted = useRef(false);

  const conversation = useConversation({
    onConnect: () => {
      // Route speak() through the agent as CUE context; the agent riffs in
      // its own voice. Returning true suppresses the local speechSynthesis.
      registerAgentSpeaker((text) => {
        try {
          conversation.sendContextualUpdate(`CUE ${text}`);
          return true;
        } catch {
          return false;
        }
      });
      Narrator.setLiveBridge((ctx) => {
        try {
          conversation.sendContextualUpdate(ctx);
        } catch {
          // session dropped mid-send; scripted fallback takes over
        }
      });
    },
    onDisconnect: () => {
      registerAgentSpeaker(null);
      Narrator.setLiveBridge(null);
    },
    onMessage: (m) => {
      if (m.role === 'agent') Narrator.postExternalLine(m.message);
    },
    onError: () => {
      registerAgentSpeaker(null);
      Narrator.setLiveBridge(null);
    },
  });

  const live = conversation.status === 'connected';
  const connecting = conversation.status === 'connecting';

  useEffect(() => {
    const s = getState();
    setMuted(s.settings.muted);
    setNarratorOn(s.settings.narratorEnabled);
    const unsubStore = subscribe((st) => {
      setMuted(st.settings.muted);
      setNarratorOn(st.settings.narratorEnabled);
    });
    const unsubCaption = Narrator.subscribe(setCaption);
    return () => {
      unsubStore();
      unsubCaption();
    };
  }, []);

  // Mute also silences the live agent (mic stays open so you can still chat).
  useEffect(() => {
    if (live) {
      try {
        conversation.setVolume({ volume: muted ? 0 : 1 });
      } catch {
        // not connected yet
      }
    }
  }, [muted, live, conversation]);

  // Turning the narrator off ends the live session too.
  useEffect(() => {
    if (!narratorOn && (live || connecting)) {
      liveWanted.current = false;
      conversation.endSession();
    }
  }, [narratorOn, live, connecting, conversation]);

  const goLive = useCallback(() => {
    if (!AGENT_ID || liveWanted.current) return;
    liveWanted.current = true;
    AudioBus.ensure();
    conversation.startSession({
      agentId: AGENT_ID,
      connectionType: 'websocket',
      dynamicVariables: { player_name: getState().profile.playerName || 'Rider' },
    });
  }, [conversation]);

  const endLive = useCallback(() => {
    liveWanted.current = false;
    conversation.endSession();
  }, [conversation]);

  const talking = caption !== null || conversation.isSpeaking;

  return (
    <div className="pointer-events-none fixed bottom-4 right-4 z-50 flex flex-col items-end gap-2">
      <style>{DOCK_CSS}</style>

      {caption && (
        <div
          key={caption.id}
          className="pointer-events-auto max-w-[250px] rounded-2xl rounded-br-md border border-zinc-700 bg-zinc-900/95 px-3 py-2 text-sm leading-snug text-zinc-100 shadow-xl backdrop-blur"
          style={{ animation: 'kk-caption-in 0.18s ease-out' }}
          aria-live="polite"
        >
          {caption.text}
        </div>
      )}

      {expanded && (
        <div className="pointer-events-auto flex items-center gap-2 rounded-2xl border border-zinc-700 bg-zinc-900/95 p-2 shadow-xl backdrop-blur">
          <button
            onClick={() => updateSettings({ narratorEnabled: !narratorOn })}
            className={`rounded-xl px-3 py-2 text-xs font-bold ${
              narratorOn ? 'bg-amber-400 text-zinc-950' : 'bg-zinc-800 text-zinc-400'
            }`}
          >
            {narratorOn ? 'Narrator ON' : 'Narrator OFF'}
          </button>
          {AGENT_ID && (
            <button
              onClick={live || connecting ? endLive : goLive}
              disabled={!narratorOn}
              className={`rounded-xl px-3 py-2 text-xs font-bold disabled:opacity-40 ${
                live
                  ? 'bg-emerald-400 text-zinc-950'
                  : connecting
                    ? 'bg-zinc-700 text-zinc-300'
                    : 'border border-amber-400/60 bg-zinc-800 text-amber-300'
              }`}
            >
              {live ? 'LIVE. Tap to end' : connecting ? 'Paddling out...' : 'Go live 🎙️'}
            </button>
          )}
        </div>
      )}

      <div className="flex items-end gap-2">
        <button
          onClick={() => setExpanded((v) => !v)}
          className="pointer-events-auto flex h-8 w-8 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900/90 text-xs text-zinc-400 shadow-lg backdrop-blur"
          aria-label="Narrator options"
        >
          {expanded ? '▾' : '▴'}
        </button>
        <button
          onClick={() => updateSettings({ muted: !muted })}
          className="pointer-events-auto relative flex h-14 w-14 items-center justify-center rounded-full border-2 border-amber-300/70 bg-gradient-to-br from-amber-400 to-amber-600 text-2xl shadow-lg"
          aria-label={muted ? 'Unmute' : 'Mute'}
        >
          <span
            className="select-none"
            style={{
              display: 'inline-block',
              animation: talking
                ? 'kk-talk 0.5s ease-in-out infinite'
                : 'kk-bob 3s ease-in-out infinite',
            }}
          >
            🏄
          </span>
          {muted && (
            <span className="absolute -bottom-1 -right-1 flex h-6 w-6 items-center justify-center rounded-full border border-zinc-700 bg-zinc-900 text-xs">
              🔇
            </span>
          )}
          {live && !muted && (
            <span className="absolute -top-0.5 -right-0.5 h-3.5 w-3.5 rounded-full border-2 border-zinc-950 bg-emerald-400" />
          )}
        </button>
      </div>
    </div>
  );
}

export default function NarratorDock() {
  return (
    <ConversationProvider>
      <DockInner />
    </ConversationProvider>
  );
}
