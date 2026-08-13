#!/usr/bin/env node
// Kamikaze Phone — ElevenLabs audio asset generator.
//
// Generates the soundtrack (Music API) and every named SFX (Sound Generation
// API) into public/audio/, then writes public/audio/manifest.json in the shape
// AudioBus (src/lib/audio.ts) expects:
//
//   { "music": { "main": "/audio/music-main.mp3" },
//     "sfx":   { "<SoundName>": "/audio/sfx-<name>.mp3", ... } }
//
// Design constraints (see docs/AUDIO.md):
// - Plain Node 18+, zero dependencies, global fetch only.
// - Idempotent: files already on disk are skipped; delete a file to regenerate.
// - Sequential requests with a small delay (rate-limit friendly).
// - The manifest only lists files that actually exist on disk, so a partial
//   run still produces a valid manifest (AudioBus synthesizes the rest).
// - Exits 0 even without ELEVENLABS_API_KEY: the game is fully playable on
//   procedural WebAudio fallbacks alone.
//
// Usage:  ELEVENLABS_API_KEY=... npm run audio:generate

import { mkdir, writeFile, stat } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT_DIR = path.join(ROOT, 'public', 'audio');
const API_BASE = 'https://api.elevenlabs.io/v1';
const OUTPUT_FORMAT = 'mp3_44100_128';
const REQUEST_DELAY_MS = 1500;
const API_KEY = process.env.ELEVENLABS_API_KEY;

// ---------------------------------------------------------------------------
// Asset definitions
// ---------------------------------------------------------------------------

const MUSIC = {
  trackId: 'main',
  file: 'music-main.mp3',
  prompt:
    '90s California surf punk instrumental, energetic skate video soundtrack, ' +
    'palm-muted guitars, driving drums, no vocals, seamless loop',
  lengthMs: 60_000,
};

// One entry per SoundName in src/lib/audio.ts. Durations 0.5-2s
// (grind-loop 2-4s, generated as a seamless loop).
const SFX = [
  { name: 'tick',        text: 'single dry mechanical clock tick, short crisp click', duration: 0.5 },
  { name: 'tick-fast',   text: 'very short high-pitched urgent tick click, faster and brighter than a clock', duration: 0.5 },
  { name: 'flip',        text: 'short cartoon whoosh flip, bright, 300ms', duration: 0.6 },
  { name: 'launch',      text: 'quick energetic whoosh of an object launched hard into the air, air swish rising', duration: 0.8 },
  { name: 'catch',       text: 'firm two-hand catch of a phone, soft slap thump, satisfying and clean', duration: 0.6 },
  { name: 'slam',        text: 'hard slam of an object hitting the ground, punchy low impact with a small rattle', duration: 0.9 },
  { name: 'bail',        text: 'comedic fail: object tumbling and clattering across the floor, sad trombone-free', duration: 1.5 },
  { name: 'grind-loop',  text: 'metal skateboard rail grind loop, gritty, seamless', duration: 3, loop: true },
  { name: 'whoosh',      text: 'fast clean air whoosh passing close by, single swish', duration: 0.7 },
  { name: 'fanfare',     text: 'short triumphant arcade victory fanfare jingle, bright and punchy', duration: 2 },
  { name: 'achievement', text: 'sparkly achievement unlock chime, ascending arpeggio, video game reward', duration: 1.5 },
  { name: 'select',      text: 'soft UI select blip, short, clean, friendly', duration: 0.5 },
  { name: 'start',       text: 'video game round start jingle, two ascending punchy notes', duration: 1 },
  { name: 'potato-tick', text: 'tense hot potato countdown tick, woodblock click, dry', duration: 0.5 },
  { name: 'potato-boom', text: 'cartoonish explosion with debris, punchy, short', duration: 1.2 },
  { name: 'crowd-oooh',  text: 'small crowd going oooh in sympathy, outdoor skatepark ambience', duration: 1.5 },
];

const sfxFile = (name) => `sfx-${name}.mp3`;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fileSize(p) {
  try { return (await stat(p)).size; } catch { return 0; }
}

const kb = (bytes) => `${(bytes / 1024).toFixed(0)} KB`;

/**
 * POST a JSON body to an ElevenLabs endpoint, expect audio bytes back.
 * Retries transient failures (429 / 5xx / network) with backoff.
 * Returns { ok: true, bytes } or { ok: false, status, error }.
 */
async function postForAudio(endpoint, body, { retries = 2 } = {}) {
  const url = `${API_BASE}${endpoint}?output_format=${OUTPUT_FORMAT}`;
  for (let attempt = 0; ; attempt++) {
    let res;
    try {
      res = await fetch(url, {
        method: 'POST',
        headers: { 'xi-api-key': API_KEY, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
    } catch (err) {
      if (attempt < retries) { await sleep(2000 * (attempt + 1)); continue; }
      return { ok: false, status: 0, error: `network error: ${err.message}` };
    }
    if (res.ok) {
      const bytes = Buffer.from(await res.arrayBuffer());
      return { ok: true, bytes };
    }
    const retriable = res.status === 429 || res.status >= 500;
    const errText = (await res.text().catch(() => '')).slice(0, 300);
    if (retriable && attempt < retries) { await sleep(3000 * (attempt + 1)); continue; }
    return { ok: false, status: res.status, error: errText || res.statusText };
  }
}

/** Write manifest.json listing ONLY files that actually exist on disk. */
async function writeManifest() {
  const manifest = { music: {}, sfx: {} };
  if (existsSync(path.join(OUT_DIR, MUSIC.file))) {
    manifest.music[MUSIC.trackId] = `/audio/${MUSIC.file}`;
  }
  for (const { name } of SFX) {
    if (existsSync(path.join(OUT_DIR, sfxFile(name)))) {
      manifest.sfx[name] = `/audio/${sfxFile(name)}`;
    }
  }
  const manifestPath = path.join(OUT_DIR, 'manifest.json');
  await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
  return manifest;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  await mkdir(OUT_DIR, { recursive: true });

  if (!API_KEY) {
    console.log('ELEVENLABS_API_KEY is not set — skipping generation.');
    console.log('');
    console.log('To generate the soundtrack + SFX:');
    console.log('  export ELEVENLABS_API_KEY=<your key>   # from elevenlabs.io profile');
    console.log('  npm run audio:generate');
    console.log('');
    const manifest = await writeManifest();
    const n = Object.keys(manifest.sfx).length + Object.keys(manifest.music).length;
    console.log(`Wrote manifest for ${n} existing asset(s) at public/audio/manifest.json.`);
    console.log('The game stays fully playable on procedural WebAudio fallbacks.');
    return;
  }

  const results = { generated: [], skipped: [], failed: [] };

  // --- Music ---------------------------------------------------------------
  const musicPath = path.join(OUT_DIR, MUSIC.file);
  if (existsSync(musicPath)) {
    results.skipped.push(MUSIC.file);
  } else {
    console.log(`Composing soundtrack (~${MUSIC.lengthMs / 1000}s, this can take a minute)...`);
    const res = await postForAudio('/music', {
      prompt: MUSIC.prompt,
      music_length_ms: MUSIC.lengthMs,
      force_instrumental: true,
    });
    if (res.ok) {
      await writeFile(musicPath, res.bytes);
      results.generated.push(`${MUSIC.file} (${kb(res.bytes.length)})`);
      console.log(`  OK ${MUSIC.file} ${kb(res.bytes.length)}`);
    } else {
      results.failed.push(`${MUSIC.file}: HTTP ${res.status} ${res.error}`);
      console.warn(`  Music API failed (HTTP ${res.status}): ${res.error}`);
      console.warn('  Continuing with SFX only — the Music API may not be enabled on this plan.');
    }
    await sleep(REQUEST_DELAY_MS);
  }

  // --- SFX -----------------------------------------------------------------
  for (const sfx of SFX) {
    const file = sfxFile(sfx.name);
    const outPath = path.join(OUT_DIR, file);
    if (existsSync(outPath)) {
      results.skipped.push(file);
      continue;
    }
    console.log(`Generating ${file} ("${sfx.text.slice(0, 50)}...")`);
    const body = {
      text: sfx.text,
      duration_seconds: sfx.duration,
      prompt_influence: 0.4,
      ...(sfx.loop ? { loop: true } : {}),
    };
    let res = await postForAudio('/sound-generation', body);
    // `loop` requires the v2 SFX model; if the API rejects it, retry without.
    if (!res.ok && res.status === 400 && sfx.loop) {
      res = await postForAudio('/sound-generation', { ...body, loop: undefined });
    }
    if (res.ok) {
      await writeFile(outPath, res.bytes);
      results.generated.push(`${file} (${kb(res.bytes.length)})`);
      console.log(`  OK ${file} ${kb(res.bytes.length)}`);
    } else {
      results.failed.push(`${file}: HTTP ${res.status} ${res.error}`);
      console.warn(`  FAILED ${file}: HTTP ${res.status} ${res.error}`);
    }
    await sleep(REQUEST_DELAY_MS);
  }

  // --- Manifest + summary --------------------------------------------------
  const manifest = await writeManifest();
  let totalBytes = 0;
  for (const file of [MUSIC.file, ...SFX.map((s) => sfxFile(s.name))]) {
    totalBytes += await fileSize(path.join(OUT_DIR, file));
  }

  console.log('');
  console.log('=== Audio generation summary ===');
  console.log(`  generated: ${results.generated.length}`);
  for (const g of results.generated) console.log(`    + ${g}`);
  console.log(`  skipped (already on disk): ${results.skipped.length}`);
  console.log(`  failed: ${results.failed.length}`);
  for (const f of results.failed) console.log(`    ! ${f}`);
  console.log(`  manifest: ${Object.keys(manifest.music).length} music track(s), ` +
    `${Object.keys(manifest.sfx).length}/${SFX.length} sfx`);
  console.log(`  total asset size: ${(totalBytes / (1024 * 1024)).toFixed(1)} MB`);
  if (results.failed.length > 0) {
    console.log('  Missing sounds fall back to procedural WebAudio synthesis at runtime.');
  }

  // A run where every request failed almost certainly means a bad key/plan.
  const attempted = results.generated.length + results.failed.length;
  if (attempted > 0 && results.generated.length === 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error('generate-audio: unexpected error:', err.message);
  process.exitCode = 1;
});
