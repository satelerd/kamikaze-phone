// Typed wrapper around PeerJS for Co-op Sync mode.
// Uses the free public PeerServer cloud, no backend: the host claims a short
// readable room id ('kmkz-' + 4 chars), the joiner dials it, and both talk
// over a DataConnection using the CoopMessage protocol below. Includes
// NTP-style clock offset estimation so two phones can share one countdown.
//
// PeerJS touches browser globals at import time, so the library is loaded
// lazily inside the class; this module is safe to import during SSR.
import type { DataConnection, Peer } from 'peerjs';
import type { TrickResult } from './types';

// ---------------------------------------------------------------------------
// Protocol (discriminated union; validated at the edge, no `any` leaks)
// ---------------------------------------------------------------------------
export type CoopGrade = TrickResult['grade'];

export type CoopMessage =
  | { t: 'hello'; name: string }
  | { t: 'ping'; sent: number }
  | { t: 'pong'; sent: number; received: number }
  | {
      /** Host schedules a synchronized 3-2-1. startAt is epoch ms in the SENDER's clock. */
      t: 'countdown';
      startAt: number;
    }
  | {
      t: 'throw';
      /** launch moment, epoch ms in the SENDER's clock */
      launchT: number;
      /** landing moment, epoch ms in the SENDER's clock */
      landT: number;
      /** seconds of freefall */
      airtime: number;
      trickId: string;
      trickName: string;
      score: number;
      grade: CoopGrade;
    }
  | { t: 'bye' };

export type ThrowMessage = Extract<CoopMessage, { t: 'throw' }>;

export type CoopRole = 'host' | 'join';

/** User-visible connection state machine. */
export type PeerStatus =
  | { s: 'idle' }
  | { s: 'starting'; role: CoopRole }
  | { s: 'waiting'; code: string; joinUrl: string }
  | { s: 'connecting'; code: string }
  | { s: 'connected'; code: string; peerName: string | null }
  | { s: 'disconnected'; reason: string }
  | { s: 'error'; message: string };

const GRADES: readonly string[] = ['S', 'A', 'B', 'C', 'BAIL'];

export function isCoopMessage(d: unknown): d is CoopMessage {
  if (typeof d !== 'object' || d === null) return false;
  const m = d as Record<string, unknown>;
  switch (m.t) {
    case 'hello':
      return typeof m.name === 'string';
    case 'ping':
      return typeof m.sent === 'number';
    case 'pong':
      return typeof m.sent === 'number' && typeof m.received === 'number';
    case 'countdown':
      return typeof m.startAt === 'number';
    case 'throw':
      return (
        typeof m.launchT === 'number' &&
        typeof m.landT === 'number' &&
        typeof m.airtime === 'number' &&
        typeof m.trickId === 'string' &&
        typeof m.trickName === 'string' &&
        typeof m.score === 'number' &&
        typeof m.grade === 'string' &&
        GRADES.includes(m.grade)
      );
    case 'bye':
      return true;
    default:
      return false;
  }
}

// ---------------------------------------------------------------------------
// Room codes + invites
// ---------------------------------------------------------------------------
const CODE_PREFIX = 'kmkz-';
// no l / i / o: those read terribly when yelled across a parking lot
const CODE_CHARS = 'abcdefghjkmnpqrstuvwxyz';

export function makeRoomCode(): string {
  let suffix = '';
  for (let i = 0; i < 4; i++) suffix += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  return CODE_PREFIX + suffix;
}

/** Accepts 'abcd', 'KMKZ-ABCD', full URLs pasted by chaos agents, etc. */
export function normalizeRoomCode(input: string): string {
  const raw = input.trim().toLowerCase();
  const fromUrl = /[?&]join=([a-z0-9-]+)/.exec(raw);
  const cleaned = (fromUrl ? fromUrl[1] : raw).replace(/[^a-z0-9-]/g, '');
  if (!cleaned) return '';
  return cleaned.startsWith(CODE_PREFIX) ? cleaned : CODE_PREFIX + cleaned.replace(/-/g, '');
}

export function makeJoinUrl(code: string): string {
  const origin = typeof window !== 'undefined' ? window.location.origin : '';
  return `${origin}/play/coop?join=${encodeURIComponent(code)}`;
}

/** Render the invite as a QR data URL (scan on the second phone). */
export async function makeJoinQR(code: string): Promise<string> {
  const qrcode = await import('qrcode');
  return qrcode.toDataURL(makeJoinUrl(code), {
    margin: 1,
    width: 280,
    color: { dark: '#09090b', light: '#fafafa' },
  });
}

// ---------------------------------------------------------------------------
// Lazy PeerJS loading + error mapping
// ---------------------------------------------------------------------------
type PeerModule = typeof import('peerjs');

let peerModule: Promise<PeerModule> | null = null;
function loadPeerJs(): Promise<PeerModule> {
  peerModule ??= import('peerjs');
  return peerModule;
}

function errType(err: unknown): string {
  if (typeof err === 'object' && err !== null && 'type' in err) {
    const t = (err as { type: unknown }).type;
    if (typeof t === 'string') return t;
  }
  return '';
}

function friendlyError(err: unknown): string {
  switch (errType(err)) {
    case 'peer-unavailable':
      return 'Room not found. Double check the code, brah.';
    case 'unavailable-id':
      return 'That room id is taken. Spin up a fresh one.';
    case 'network':
      return 'Lost the signal tower. Check your connection.';
    case 'browser-incompatible':
      return 'This browser cannot do WebRTC. Try Chrome or Safari.';
    default:
      return err instanceof Error && err.message
        ? err.message
        : 'Something gnarly happened to the connection.';
  }
}

const OPEN_TIMEOUT_MS = 15000;
const CONNECT_TIMEOUT_MS = 15000;
const HOST_ID_RETRIES = 4;
const PING_ROUNDS = 10;
const PING_TIMEOUT_MS = 1500;
const PING_SPACING_MS = 40;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/** Create a Peer and wait for it to register with the PeerServer cloud. */
function openPeer(PeerCtor: PeerModule['default'], id?: string): Promise<Peer> {
  return new Promise((resolve, reject) => {
    const peer = id ? new PeerCtor(id) : new PeerCtor();
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      peer.destroy();
      reject(new Error('Signal tower timeout. Try again.'));
    }, OPEN_TIMEOUT_MS);
    peer.once('open', () => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(peer);
    });
    peer.once('error', (err) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      peer.destroy();
      reject(err);
    });
  });
}

// ---------------------------------------------------------------------------
// CoopPeer
// ---------------------------------------------------------------------------
export class CoopPeer {
  readonly myName: string;
  role: CoopRole | null = null;
  code: string | null = null;
  /** Estimated partner clock minus local clock (ms, Date.now domain); null until measured. */
  clockOffset: number | null = null;
  /** Median round trip of the last clock sync (ms). */
  rttMs: number | null = null;

  private peer: Peer | null = null;
  private conn: DataConnection | null = null;
  private statusValue: PeerStatus = { s: 'idle' };
  private remoteNameValue: string | null = null;
  private closing = false;
  private messageListeners = new Set<(m: CoopMessage) => void>();
  private statusListeners = new Set<(st: PeerStatus) => void>();
  private pongWaiters = new Map<number, (received: number) => void>();

  constructor(myName: string) {
    this.myName = myName || 'Rider';
  }

  get status(): PeerStatus {
    return this.statusValue;
  }

  get remoteName(): string | null {
    return this.remoteNameValue;
  }

  get connected(): boolean {
    return this.conn?.open === true;
  }

  onMessage(cb: (m: CoopMessage) => void): () => void {
    this.messageListeners.add(cb);
    return () => this.messageListeners.delete(cb);
  }

  onStatus(cb: (st: PeerStatus) => void): () => void {
    this.statusListeners.add(cb);
    return () => this.statusListeners.delete(cb);
  }

  /** Host: claim a readable room id and wait for a partner. Resolves with the code. */
  async host(): Promise<string> {
    if (typeof window === 'undefined') throw new Error('Co-op needs a browser');
    this.role = 'host';
    this.setStatus({ s: 'starting', role: 'host' });
    const { default: PeerCtor } = await loadPeerJs();
    let lastErr: unknown = null;
    for (let attempt = 0; attempt < HOST_ID_RETRIES; attempt++) {
      const code = makeRoomCode();
      try {
        const peer = await openPeer(PeerCtor, code);
        if (this.closing) {
          peer.destroy();
          throw new Error('Cancelled');
        }
        this.peer = peer;
        this.code = code;
        this.wirePeer(peer);
        peer.on('connection', (conn) => this.adopt(conn));
        this.setStatus({ s: 'waiting', code, joinUrl: makeJoinUrl(code) });
        return code;
      } catch (err) {
        lastErr = err;
        // id collision on the public cloud: roll a new code and retry
        if (errType(err) !== 'unavailable-id') break;
      }
    }
    const message = friendlyError(lastErr);
    this.setStatus({ s: 'error', message });
    throw new Error(message);
  }

  /** Join: dial a host's room code (from the ?join= param or manual entry). */
  async join(codeInput: string): Promise<void> {
    if (typeof window === 'undefined') throw new Error('Co-op needs a browser');
    const code = normalizeRoomCode(codeInput);
    if (!code) {
      const message = 'Type the room code first.';
      this.setStatus({ s: 'error', message });
      throw new Error(message);
    }
    this.role = 'join';
    this.code = code;
    this.setStatus({ s: 'connecting', code });
    try {
      const { default: PeerCtor } = await loadPeerJs();
      const peer = await openPeer(PeerCtor);
      if (this.closing) {
        peer.destroy();
        return;
      }
      this.peer = peer;
      this.wirePeer(peer);
      const conn = peer.connect(code, { reliable: true, label: 'kamikaze-coop' });
      this.adopt(conn);
      setTimeout(() => {
        if (!this.closing && this.conn === conn && !conn.open && this.statusValue.s === 'connecting') {
          this.setStatus({ s: 'error', message: 'Could not reach that room. Maybe the host bailed?' });
          this.destroyPeer();
        }
      }, CONNECT_TIMEOUT_MS);
    } catch (err) {
      const message = friendlyError(err);
      this.setStatus({ s: 'error', message });
      throw new Error(message);
    }
  }

  /** Send a protocol message. Returns false when the channel is not open. */
  send(m: CoopMessage): boolean {
    return this.sendRaw(m);
  }

  /**
   * NTP-style clock sync: median of `rounds` round trips.
   * offset = ((t1 - t0) + (t2 - t3)) / 2 with t1 = t2 = the partner's receive
   * timestamp (they pong immediately). Positive offset = partner clock ahead.
   */
  async measureClockOffset(rounds = PING_ROUNDS): Promise<{ offset: number; rtt: number }> {
    const offsets: number[] = [];
    const rtts: number[] = [];
    for (let i = 0; i < rounds; i++) {
      try {
        const r = await this.pingOnce();
        offsets.push(r.offset);
        rtts.push(r.rtt);
      } catch {
        // dropped ping: skip it, the median forgives
      }
      await sleep(PING_SPACING_MS);
    }
    if (!offsets.length) throw new Error('Clock sync failed: no pong came back.');
    this.clockOffset = median(offsets);
    this.rttMs = Math.round(median(rtts));
    return { offset: this.clockOffset, rtt: this.rttMs };
  }

  /** Convert a partner timestamp (their Date.now) into our clock. */
  toLocalTime(remoteEpochMs: number): number {
    return remoteEpochMs - (this.clockOffset ?? 0);
  }

  /** Convert one of our timestamps into the partner's clock. */
  toRemoteTime(localEpochMs: number): number {
    return localEpochMs + (this.clockOffset ?? 0);
  }

  /** Clean close: wave goodbye, tear everything down. */
  close(): void {
    if (this.closing) return;
    this.closing = true;
    this.sendRaw({ t: 'bye' });
    try {
      this.conn?.close({ flush: true });
    } catch {
      // already gone
    }
    this.destroyPeer();
    this.pongWaiters.clear();
    this.statusValue = { s: 'idle' };
    this.messageListeners.clear();
    this.statusListeners.clear();
  }

  // -------------------------------------------------------------------------
  // internals
  // -------------------------------------------------------------------------
  private setStatus(st: PeerStatus): void {
    this.statusValue = st;
    this.statusListeners.forEach((cb) => cb(st));
  }

  private destroyPeer(): void {
    try {
      this.peer?.destroy();
    } catch {
      // already gone
    }
    this.peer = null;
    this.conn = null;
  }

  private wirePeer(peer: Peer): void {
    peer.on('error', (err) => {
      if (this.closing) return;
      // If the data channel is alive, a signalling-server hiccup is not fatal.
      if (this.conn?.open) return;
      this.setStatus({ s: 'error', message: friendlyError(err) });
      this.destroyPeer();
    });
    peer.on('disconnected', () => {
      // Lost the signalling server, not the data channel. Best-effort rejoin
      // so the room id stays claimed; the game keeps flowing either way.
      if (!this.closing && !peer.destroyed) {
        try {
          peer.reconnect();
        } catch {
          // best effort only
        }
      }
    });
  }

  private adopt(conn: DataConnection): void {
    if (this.conn && this.conn !== conn && this.conn.open) {
      // one partner per room: politely refuse extra connections
      conn.on('open', () => conn.close());
      return;
    }
    this.conn = conn;
    conn.on('open', () => {
      if (this.closing) return;
      this.setStatus({ s: 'connected', code: this.code ?? conn.peer, peerName: this.remoteNameValue });
      this.sendRaw({ t: 'hello', name: this.myName });
    });
    conn.on('data', (d) => this.handleData(d));
    conn.on('close', () => {
      if (this.closing) return;
      this.conn = null;
      if (this.statusValue.s === 'disconnected' || this.statusValue.s === 'error') return;
      this.setStatus({ s: 'disconnected', reason: 'Connection dropped. Your partner vanished into the tube.' });
    });
    conn.on('error', (err) => {
      if (this.closing) return;
      this.conn = null;
      this.setStatus({ s: 'disconnected', reason: friendlyError(err) });
    });
  }

  private handleData(d: unknown): void {
    if (!isCoopMessage(d)) return;
    switch (d.t) {
      case 'ping':
        this.sendRaw({ t: 'pong', sent: d.sent, received: Date.now() });
        break;
      case 'pong': {
        const waiter = this.pongWaiters.get(d.sent);
        if (waiter) {
          this.pongWaiters.delete(d.sent);
          waiter(d.received);
        }
        break;
      }
      case 'hello':
        this.remoteNameValue = d.name;
        if (this.statusValue.s === 'connected') {
          this.setStatus({ ...this.statusValue, peerName: d.name });
        }
        break;
      case 'bye':
        this.setStatus({ s: 'disconnected', reason: 'Your partner bailed out of the session.' });
        break;
      default:
        break;
    }
    this.messageListeners.forEach((cb) => cb(d));
  }

  private sendRaw(m: CoopMessage): boolean {
    if (!this.conn?.open) return false;
    try {
      void this.conn.send(m);
      return true;
    } catch {
      return false;
    }
  }

  private pingOnce(): Promise<{ offset: number; rtt: number }> {
    return new Promise((resolve, reject) => {
      const t0 = Date.now();
      const timer = setTimeout(() => {
        this.pongWaiters.delete(t0);
        reject(new Error('pong timeout'));
      }, PING_TIMEOUT_MS);
      this.pongWaiters.set(t0, (received) => {
        clearTimeout(timer);
        const t3 = Date.now();
        resolve({ offset: (received - t0 + (received - t3)) / 2, rtt: t3 - t0 });
      });
      if (!this.sendRaw({ t: 'ping', sent: t0 })) {
        clearTimeout(timer);
        this.pongWaiters.delete(t0);
        reject(new Error('channel closed'));
      }
    });
  }
}
