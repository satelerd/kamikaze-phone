// Bodhi Bytes: the scripted commentary brain behind the surfer narrator.
// Modes attach() a session and feed GameEvents + TrickResults; the narrator
// turns them into short surfer lines, rate-limited and variety-rotated, and
// routes them through speak() (which prefers the live ElevenLabs agent when
// the dock has one connected, falling back to speechSynthesis).
import { speak } from './speech';
import { getState } from './store';
import type { GameEvent, TrickResult } from './types';

export interface NarratorLine {
  id: number;
  text: string;
  at: number;
}

type CaptionListener = (line: NarratorLine | null) => void;
/** The dock registers this while a live ElevenLabs session is connected. */
type LiveBridge = (contextText: string) => void;

const RATE_LIMIT_MS = 2500;
const LINE_TTL_MS = 6000;
const IDLE_NUDGE_MS = 45000;
const LAUNCH_LINE_COOLDOWN_MS = 9000;
const MAX_QUEUE = 4;

// ---------------------------------------------------------------------------
// Line pools. Templates may use {name} {trick} {score} {callout} {airtime}
// {spins} {streak}. Copy rule: no em dashes, PG, short and punchy.
// ---------------------------------------------------------------------------
const LINES = {
  gradeS: [
    'COWABUNGA!! {trick}! That was straight-up LEGENDARY, brah!',
    'S-TIER!! {callout} I am LOSING it over here!',
    'STOP EVERYTHING. {trick} for {score}?! Hall of fame, dude!',
    'The ocean just applauded, brah. {trick}. {score} points of pure stoke!',
    'THAT. WAS. RADICAL. {trick}! Somebody frame this moment!',
  ],
  gradeA: [
    '{callout} Righteous ride, brah!',
    'So stoked! {trick} for {score}. Butter smooth, dude.',
    'That phone was DANCING, {name}! {trick}!',
    'Gnarly! {trick}, stomped like a champ.',
    'A-grade air, brah! {callout}',
  ],
  gradeB: [
    '{trick}! Solid, brah. Wax it up and go bigger.',
    'Not bad, not gnarly. {score} points of medium stoke.',
    'B-grade, dude. The stoke is there, the spin wants more.',
    'Decent pop on that {trick}. Now send it like you mean it!',
  ],
  gradeC: [
    'Hey, it flew. Technically. {score} points, brah.',
    'C is for come on dude, you got more than that!',
    'Baby waves, {name}. Paddle back out and send it.',
    'That was a warm-up, right? Tell me that was a warm-up.',
  ],
  bail: [
    'BAIL! The towel remembers, dude. The towel forgives.',
    'Ohhh brah, that phone ate SAND. Hug it and go again.',
    'Gravity one, you zero. Still love you, dude.',
    'Total yard sale, brah! Check the screen, check your soul, go again.',
    'WIPEOUT! Good thing you wrapped it in a towel. You DID wrap it, right?',
    'The landing said no, brah. The comeback says yes!',
  ],
  launch: [
    'Up she goes!',
    'SEND IT, BRAH!',
    'Air time, baby!',
    'And we have liftoff, dude!',
  ],
  streak: [
    'THREE clean catches in a row, {name}! You are heating up, brah!',
    'FOUR straight! The streak is ALIVE, dude. Do not blink!',
    'FIVE IN A ROW! You are surfing the cosmos now, brah!',
    '{streak} STRAIGHT! A legend is being written in mid-air, dude!',
  ],
  sessionBest: [
    'New session best: {score}! The bar has been RAISED, brah!',
    'Personal high tide, dude! {score} points, best of the sesh!',
  ],
  allTimeBest: [
    'STOP EVERYTHING. NEW ALL-TIME RECORD: {score} points! Cowabunga does not even cover it!',
    'HISTORY, {name}! {score} points, best throw of your LIFE!',
  ],
  bigAir: [
    'Biggest air of the sesh: {airtime} seconds of pure float, dude!',
    'MASSIVE hang time, brah! {airtime} seconds in the blue!',
  ],
  idle: [
    'You gonna throw it or marry it, brah?',
    'The sky misses your phone, dude. Just saying.',
    'Towel is wrapped, sun is out, and we are... standing here. Send it!',
    'I have seen glaciers warm up faster, brah. Let us ride!',
    'Phone check: still in your hand. Fix that, dude.',
  ],
} as const;

type PoolName = keyof typeof LINES;

const MODE_INTROS: Record<string, string> = {
  'free-ride': 'Free Ride, baby! No judges, no rules, just you, the phone, and the sky. Show me something radical!',
  'trick-lab': 'Welcome to the Trick Lab, brah! Cameras hot, physics nerds ready. Make it cinematic!',
  grind: 'Rail Grind time, dude! Find that steel and let the phone surf it!',
  'fridge-surfer': 'Fridge Surfer! Stick that landing on the magnet, brah!',
  eclipse: 'Eclipse run, dude! Throw it through the darkness and let there be light!',
  scream: 'Scream Meter, baby! The louder you hype, the higher you score. Warm up those lungs!',
  'charger-bullseye': 'Charger Bullseye, brah! Land it on the pad and juice up that score!',
  'nfc-spots': 'Spot claiming time, dude! Slam it on the tag and make it yours!',
  'hot-potato': 'HOT POTATO! Wrap it, pass it, do NOT be holding it when it blows, brah!',
  coop: 'Co-op Sync! Two phones, two riders, one heartbeat. Feel the vibe, dudes!',
};
const DEFAULT_INTRO = 'Session is ON, brah! Wrap it in the towel, warm up the wrists, and let us shred!';

interface QueuedLine {
  text: string;
  expiresAt: number;
  /** higher wins when the queue overflows */
  priority: number;
}

// Small seeded RNG (mulberry32) for deterministic-ish variety per session.
function makeRng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

class NarratorImpl {
  private mode: string | null = null;
  private rng: () => number = makeRng(1337);
  private decks = new Map<PoolName, number[]>();
  private lastLineByPool = new Map<PoolName, string>();
  private queue: QueuedLine[] = [];
  private lastSpokeAt = 0;
  private pumpTimer: ReturnType<typeof setTimeout> | null = null;
  private hideTimer: ReturnType<typeof setTimeout> | null = null;
  private idleTimer: ReturnType<typeof setTimeout> | null = null;
  private lastLaunchLineAt = 0;
  private lineId = 0;
  private listeners = new Set<CaptionListener>();
  private liveBridge: LiveBridge | null = null;

  // per-session tracking
  private streak = 0;
  private sessionBest = 0;
  private sessionBiggestAir = 0;
  private allTimeBestAtAttach = 0;

  // -------------------------------------------------------------------------
  // Session lifecycle
  // -------------------------------------------------------------------------
  attach(modeId: string): void {
    this.detach();
    this.mode = modeId;
    this.rng = makeRng(Date.now() & 0xffffffff);
    this.decks.clear();
    this.streak = 0;
    this.sessionBest = 0;
    this.sessionBiggestAir = 0;
    this.allTimeBestAtAttach = getState().bestScore;
    const intro = MODE_INTROS[modeId] ?? DEFAULT_INTRO;
    this.enqueue(intro, 2);
    this.liveBridge?.(`EVENT ${JSON.stringify({ event: 'session-start', mode: modeId })}`);
    this.armIdleTimer();
  }

  detach(): void {
    this.mode = null;
    this.queue = [];
    if (this.pumpTimer) clearTimeout(this.pumpTimer);
    this.pumpTimer = null;
    if (this.idleTimer) clearTimeout(this.idleTimer);
    this.idleTimer = null;
  }

  get attached(): boolean {
    return this.mode !== null;
  }

  // -------------------------------------------------------------------------
  // Inputs
  // -------------------------------------------------------------------------
  onEvent(e: GameEvent): void {
    if (!this.mode) return;
    this.armIdleTimer();
    if (e.type === 'launch') {
      const now = Date.now();
      if (
        now - this.lastLaunchLineAt > LAUNCH_LINE_COOLDOWN_MS &&
        this.queue.length === 0 &&
        this.rng() < 0.35
      ) {
        this.lastLaunchLineAt = now;
        this.enqueue(this.draw('launch', {}), 1);
      }
    }
  }

  /**
   * Feed a completed trick. Returns the composed reaction line so UIs
   * (TrickCard) can print what Bodhi said about this exact throw.
   */
  onTrick(result: TrickResult): string {
    this.armIdleTimer();
    const isClean = result.features.caught && result.grade !== 'BAIL';
    this.streak = isClean ? this.streak + 1 : 0;

    const newAllTime = result.score > this.allTimeBestAtAttach;
    if (newAllTime) this.allTimeBestAtAttach = result.score;
    const newSessionBest = result.score > this.sessionBest;
    if (newSessionBest) this.sessionBest = result.score;
    const newBigAir = result.features.airtime > this.sessionBiggestAir;
    if (newBigAir) this.sessionBiggestAir = result.features.airtime;

    const vars = this.varsFor(result);
    const pool: PoolName =
      result.grade === 'BAIL' ? 'bail'
      : result.grade === 'S' ? 'gradeS'
      : result.grade === 'A' ? 'gradeA'
      : result.grade === 'B' ? 'gradeB'
      : 'gradeC';
    const line = this.draw(pool, vars);

    // Secondary flourish: records beat streaks; streaks fire from 3 up.
    let secondary: string | null = null;
    if (newAllTime && result.grade !== 'BAIL') {
      secondary = this.draw('allTimeBest', vars);
    } else if (newSessionBest && this.sessionBest > 0 && result.grade === 'S') {
      secondary = this.draw('sessionBest', vars);
    } else if (this.streak >= 3) {
      const idx = Math.min(this.streak - 3, LINES.streak.length - 1);
      secondary = this.fill(LINES.streak[idx], vars);
    } else if (newBigAir && result.features.airtime >= 1.0) {
      secondary = this.draw('bigAir', vars);
    }

    this.enqueue(line, 3);
    if (secondary) this.enqueue(secondary, 2);

    // Live agent: one compact JSON line per trick; the agent riffs on it.
    this.liveBridge?.(
      `EVENT ${JSON.stringify({
        event: 'trick',
        trick: result.trickName,
        grade: result.grade,
        score: result.score,
        airtime: Number(result.features.airtime.toFixed(2)),
        height: Number(result.features.height.toFixed(2)),
        spins: Number(
          (Math.max(
            Math.abs(result.features.rotX),
            Math.abs(result.features.rotY),
            Math.abs(result.features.rotZ),
          ) / 360).toFixed(1),
        ),
        caught: result.features.caught,
        streak: this.streak,
        newBest: newAllTime,
        callout: result.callout,
      })}`,
    );

    return line;
  }

  // -------------------------------------------------------------------------
  // Caption stream (UIs subscribe; null = caption hidden)
  // -------------------------------------------------------------------------
  subscribe(cb: CaptionListener): () => void {
    this.listeners.add(cb);
    return () => {
      this.listeners.delete(cb);
    };
  }

  /** Push a line spoken by the live agent into the caption stream. */
  postExternalLine(text: string): void {
    if (!text.trim()) return;
    this.emitCaption(text);
  }

  /**
   * The dock wires this while a live ElevenLabs session is up so trick events
   * flow to the agent as contextual updates. Pass null on disconnect.
   */
  setLiveBridge(fn: LiveBridge | null): void {
    this.liveBridge = fn;
  }

  get liveConnected(): boolean {
    return this.liveBridge !== null;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------
  private varsFor(result: TrickResult): Record<string, string> {
    const spins = Math.max(
      Math.abs(result.features.rotX),
      Math.abs(result.features.rotY),
      Math.abs(result.features.rotZ),
    ) / 360;
    return {
      name: getState().profile.playerName || 'brah',
      trick: result.trickName,
      score: String(result.score),
      callout: result.callout,
      airtime: result.features.airtime.toFixed(1),
      spins: spins.toFixed(1),
      streak: String(this.streak),
    };
  }

  private fill(template: string, vars: Record<string, string>): string {
    return template.replace(/\{(\w+)\}/g, (_, key: string) => vars[key] ?? '');
  }

  /** Seeded deck rotation per pool: full shuffle, no immediate repeats. */
  private draw(pool: PoolName, vars: Record<string, string>): string {
    const options = LINES[pool];
    let deck = this.decks.get(pool);
    if (!deck || deck.length === 0) {
      deck = options.map((_, i) => i);
      for (let i = deck.length - 1; i > 0; i--) {
        const j = Math.floor(this.rng() * (i + 1));
        [deck[i], deck[j]] = [deck[j], deck[i]];
      }
      const last = this.lastLineByPool.get(pool);
      if (deck.length > 1 && last !== undefined && options[deck[0]] === last) {
        [deck[0], deck[1]] = [deck[1], deck[0]];
      }
      this.decks.set(pool, deck);
    }
    const idx = deck.shift()!;
    this.lastLineByPool.set(pool, options[idx]);
    return this.fill(options[idx], vars);
  }

  private enqueue(text: string, priority: number): void {
    if (typeof window === 'undefined') return;
    const { settings } = getState();
    if (settings.muted || !settings.narratorEnabled) return;
    this.queue.push({ text, priority, expiresAt: Date.now() + LINE_TTL_MS });
    if (this.queue.length > MAX_QUEUE) {
      // drop the oldest lowest-priority line
      let dropIdx = 0;
      for (let i = 1; i < this.queue.length - 1; i++) {
        if (this.queue[i].priority < this.queue[dropIdx].priority) dropIdx = i;
      }
      this.queue.splice(dropIdx, 1);
    }
    this.pump();
  }

  private pump(): void {
    if (this.pumpTimer) return;
    const wait = Math.max(0, this.lastSpokeAt + RATE_LIMIT_MS - Date.now());
    this.pumpTimer = setTimeout(() => {
      this.pumpTimer = null;
      this.deliver();
    }, wait);
  }

  private deliver(): void {
    const now = Date.now();
    this.queue = this.queue.filter((l) => l.expiresAt > now); // drop stale
    const next = this.queue.shift();
    if (!next) return;
    const { settings } = getState();
    if (!settings.muted && settings.narratorEnabled) {
      this.lastSpokeAt = now;
      speak(next.text, { style: 'surfer' });
      // In live mode the agent speaks its own riff; the scripted caption is
      // still emitted so the UI always has something to show instantly.
      this.emitCaption(next.text);
    }
    if (this.queue.length) this.pump();
  }

  private emitCaption(text: string): void {
    const line: NarratorLine = { id: ++this.lineId, text, at: Date.now() };
    this.listeners.forEach((cb) => cb(line));
    if (this.hideTimer) clearTimeout(this.hideTimer);
    const visibleMs = Math.min(8000, Math.max(3000, 2200 + text.length * 55));
    this.hideTimer = setTimeout(() => {
      this.hideTimer = null;
      this.listeners.forEach((cb) => cb(null));
    }, visibleMs);
  }

  private armIdleTimer(): void {
    if (typeof window === 'undefined') return;
    if (this.idleTimer) clearTimeout(this.idleTimer);
    if (!this.mode) return;
    this.idleTimer = setTimeout(() => {
      if (!this.mode) return;
      this.enqueue(this.draw('idle', { name: getState().profile.playerName || 'brah' }), 1);
      this.liveBridge?.(`EVENT ${JSON.stringify({ event: 'idle', mode: this.mode })}`);
      this.armIdleTimer(); // re-arm for the next nudge
    }, IDLE_NUDGE_MS);
  }
}

export const Narrator = new NarratorImpl();
