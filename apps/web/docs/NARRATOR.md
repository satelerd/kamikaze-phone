# Bodhi Bytes, the Kamikaze Narrator

The radical 90s California surfer who narrates the whole game. He lives in two layers:
a fully offline scripted brain (`src/lib/narrator.ts`) and an optional live ElevenLabs
Conversational AI agent (`convai/`). Scripted mode is the default and needs zero keys,
zero network. Live mode upgrades him to a real voice that riffs on your tricks.

## Character sheet

| | |
|---|---|
| Name | Bodhi Bytes |
| Vibe | Fully stoked 90s SoCal surfer, live sports commentator energy |
| Vocabulary | radical, gnarly, righteous, bodacious, cowabunga, brah, dude, send it, shred the gnar, stomped it, wipeout, yard sale |
| Line length | 1 to 2 short sentences, always |
| Rating | Strictly PG. Roasts the bail, never the person |
| Religion | Towel safety. Wrap the phone. The towel forgives |
| Reactions | S grade: loses his mind. A: proud coach. B: push to go bigger. C: gentle tease. BAIL: loving roast plus towel gospel |
| Extras | Streak hype from 3 clean catches, record announcements, idle nudges after 45s ("You gonna throw it or marry it, brah?") |

## Architecture

```
game mode (e.g. Free Ride)
  |  Narrator.attach('free-ride')          mode-aware intro
  |  Narrator.onEvent(gameEvent)           occasional launch lines, idle reset
  |  Narrator.onTrick(trickResult) -> line grade reaction + callout + streak/record
  v
Narrator (src/lib/narrator.ts)  scripted brain, singleton
  - template pools per situation, seeded deck rotation, no immediate repeats
  - rate limit: max 1 line / 2.5s, queue of 4, stale lines dropped (6s TTL)
  - captions: Narrator.subscribe(cb) emits {id,text,at} then null on auto-hide
  v
speak(text, {style:'surfer'})  (src/lib/speech.ts)
  - live agent registered?  -> routed to ElevenLabs agent as a CUE context line
  - otherwise               -> speechSynthesis (surfer rate/pitch), music ducks
```

Live mode (NarratorDock "Go live"):

- `useConversation` (`@elevenlabs/react`, inside `ConversationProvider`) starts a
  WebSocket session with the agent id from `NEXT_PUBLIC_ELEVENLABS_AGENT_ID`.
- On connect the dock calls `registerAgentSpeaker(fn)` so `speak()` routes scripted
  lines to the agent as `CUE <text>` contextual updates (inspiration, not scripture),
  and `Narrator.setLiveBridge(fn)` so every trick streams as a compact JSON line:
  `EVENT {"event":"trick","trick":"Double Pancake","grade":"A","score":72,...}`.
  The agent riffs on those in his own voice.
- Agent responses come back through `onMessage` and are pushed into the caption
  stream (`Narrator.postExternalLine`), so captions always match what you hear.
- On disconnect (or error) the dock calls `registerAgentSpeaker(null)` and
  `setLiveBridge(null)`: scripted lines + speechSynthesis take over instantly.
- No agent id configured? The "Go live" button simply does not render. Scripted
  mode is the whole product on its own.

## The agent as code (`convai/`)

Follows the freezeme pattern: `agents.json` is the lockfile (config path + agent id),
`agent_configs/kamikaze-narrator.json` is the full agent definition (persona prompt,
first message, reaction rules for EVENT/CUE updates, evaluation criteria, widget).

- **Voice**: `IKne3meq5aSn9XLyUdCD` ("Charlie"), a prebuilt ElevenLabs voice:
  casual, energetic, laid-back male. The closest stock voice to a stoked surfer
  bro without cloning anything. Stability is set low (0.32) for expressiveness,
  speed slightly up (1.04) for commentary pace.
- **TTS model**: `eleven_turbo_v2` (low latency, good enough quality for hype lines).
- **LLM**: `gemini-2.5-flash`, temperature 0.8.
- **Current agent id**: `agent_8801kzvwmxedfzb9q0he9x9ed41s` (already created and
  recorded in `convai/agents.json` by the CLI).

### Syncing changes

The `elevenlabs` CLI must be authenticated once (`elevenlabs auth login`, key never
lives in the repo). Then, from `convai/`:

```bash
cd convai && elevenlabs agents push --no-ui
```

Edit `agent_configs/kamikaze-narrator.json`, push again, done. `elevenlabs agents
status --no-ui` shows drift. If the agent was never created (fresh workspace), the
same push command creates it and writes the new id into `agents.json`.

## Env var

```bash
# .env.local at the repo root
NEXT_PUBLIC_ELEVENLABS_AGENT_ID=agent_8801kzvwmxedfzb9q0he9x9ed41s
```

This is the only thing the web app needs: it is a public agent id (auth disabled,
daily call limit capped in platform_settings), not a secret. The ElevenLabs API key
is only ever used by the CLI to sync the config.

## Mute and controls (NarratorDock)

The dock floats bottom-right on every page (rendered by `src/app/layout.tsx`):

- **Tap the surfer** = mute/unmute everything (`updateSettings({muted})`). A 🔇
  badge shows the state. Mute also drops the live agent volume to zero (mic stays
  open so you can still talk to him).
- **Chevron** expands a row with: Narrator ON/OFF (`narratorEnabled`, kills lines
  entirely and ends any live session) and Go live / end live when an agent id is
  configured. A green dot on the avatar = live session connected.
- Idle bob animation; talk animation while a caption is visible or the live agent
  is speaking. The wrapper is `pointer-events-none` so only the visible controls
  ever intercept taps.

## How a mode feeds the narrator

```ts
import { Narrator } from '@/lib/narrator';

Narrator.attach('my-mode');            // session start, mode-aware intro
Narrator.onEvent(gameEvent);           // forward ThrowTracker events
const line = Narrator.onTrick(result); // after classifyThrow; line for the UI card
Narrator.detach();                     // session end
```

Free Ride (`src/app/play/free-ride/page.tsx` + `src/modes/free-ride/`) is the
reference integration: sensors, wake lock, music, phase indicator, stats bar,
TrickCard feed, achievements hook (guarded dynamic import), and a desktop
"Simulate session" demo that replays `demoSession()` through the same pipeline.
