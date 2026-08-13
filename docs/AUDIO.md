# Audio

How sound works in Kamikaze Phone: an `AudioBus` with music/sfx/voice channels, generated
ElevenLabs assets in `public/audio/`, and procedural WebAudio fallbacks so the game is fully
playable with zero downloaded assets.

## Architecture

```
public/audio/manifest.json ──► AudioBus (src/lib/audio.ts) ──► WebAudio graph
public/audio/*.mp3                 │                             ├─ musicGain ─► destination
                                   │ missing sound?              └─ sfxGain   ─► destination
                                   └─► procedural synth fallback
Narrator (ElevenLabs agent / speechSynthesis) ──► voice channel, ducks music
```

- **`AudioBus`** (`src/lib/audio.ts`) is a singleton with three logical channels:
  - **music**: one looping soundtrack (`playMusic('main')` / `stopMusic()`), gain from
    `settings.musicVolume`.
  - **sfx**: one-shots via `play(name)` plus loops via `startLoop` / `setLoopIntensity` /
    `stopLoop` (used for the rail-grind rumble), gain from `settings.sfxVolume`.
  - **voice**: the narrator speaks outside the bus (ElevenLabs agent audio or
    `speechSynthesis`); the bus cooperates via `duck(true|false)`, which ramps music to 25%
    while the narrator talks.
- **Unlock**: `ensure()` must be called from a user gesture (it is, by the mode screens);
  it creates the `AudioContext`, wires gains, subscribes to settings (global mute lives in
  the store) and fetches the manifest.
- **Manifest**: `/audio/manifest.json` with shape
  `{"music": {"main": "/audio/music-main.mp3"}, "sfx": {"<SoundName>": "/audio/sfx-<name>.mp3"}}`.
  Buffers are fetched and decoded lazily on first play, then cached.
- **Procedural fallbacks**: every `SoundName` has a WebAudio synthesis recipe (oscillator
  sweeps, filtered noise, arpeggios) in `AudioBusImpl.synth()`. Any sound missing from the
  manifest, failing to fetch, or failing to decode falls back silently to synthesis. No key,
  no assets, no network: the game still sounds like a game.

The `SoundName` union (16 sounds): `tick`, `tick-fast`, `flip`, `launch`, `catch`, `slam`,
`bail`, `grind-loop`, `whoosh`, `fanfare`, `achievement`, `select`, `start`, `potato-tick`,
`potato-boom`, `crowd-oooh`.

## Generating the assets

```bash
export ELEVENLABS_API_KEY=...   # see "Where the key comes from"
npm run audio:generate          # runs scripts/generate-audio.mjs
```

`scripts/generate-audio.mjs` (plain Node 18+, zero deps, global `fetch`):

1. **Soundtrack** via the ElevenLabs Music API (`POST /v1/music`): one ~60s instrumental,
   prompt "90s California surf punk instrumental, energetic skate video soundtrack,
   palm-muted guitars, driving drums, no vocals, seamless loop", `force_instrumental`,
   saved as `public/audio/music-main.mp3`. If the Music API errors (not enabled on every
   plan), the script logs it and continues with SFX only.
2. **SFX** via the Sound Generation API (`POST /v1/sound-generation`): one request per
   `SoundName` with a tailored prompt, durations 0.5-2s (grind-loop 2-4s with `loop: true`
   for a seamless loop), `prompt_influence: 0.4`, saved as `public/audio/sfx-<name>.mp3`.
3. **Manifest**: rewrites `public/audio/manifest.json` listing only files that actually
   exist on disk, so a partial run still yields a valid manifest.

Behavior notes:

- **Idempotent**: existing files are skipped. Requests run sequentially with a 1.5s delay
  (rate-limit friendly) and retry transient 429/5xx failures with backoff.
- **Keyless**: without `ELEVENLABS_API_KEY` the script prints setup instructions, writes a
  manifest of whatever already exists (or `{"music":{},"sfx":{}}`) and exits 0.
- **Committed**: the mp3s and manifest are meant to be committed; players should never need
  an API key.

## Where the key comes from

- Create one at elevenlabs.io (Profile → API Keys) and export it as `ELEVENLABS_API_KEY`.

The key is only ever read from the environment at generation time. It must never be
committed, must never appear in the manifest or any repo file, and is not needed at runtime.

## Regenerating

- One sound: delete its mp3 (e.g. `rm public/audio/sfx-flip.mp3`), tweak the prompt in
  `scripts/generate-audio.mjs` if desired, re-run `npm run audio:generate`.
- Everything: `rm public/audio/*.mp3 && npm run audio:generate`.
- The manifest is rebuilt from disk on every run; never edit it by hand.

## Asset size guidance

Current footprint is ~1.2 MB (938 KB music + ~290 KB across 16 SFX at mp3 44.1 kHz
128 kbps). Keep the total under ~15 MB:

- Music dominates: 128 kbps ≈ 1 MB per minute. Keep the loop at 60-90s; prefer one great
  loop over multiple tracks. Add new tracks under `music.<trackId>` in the script's config.
- SFX are cheap (9-48 KB each); keep them 0.5-2s. Long ambiences belong in music.
- If the budget ever gets tight, drop `OUTPUT_FORMAT` in the script to `mp3_44100_96`
  before reaching for fewer sounds.
