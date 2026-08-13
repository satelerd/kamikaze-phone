// NFC Spots logic: minimal Web NFC ambient types (not in lib.dom), plus the
// localStorage spot registry. Claim tags like skate spots; land on them to score.
export interface NDEFReadingEventLike extends Event {
  serialNumber: string;
}

export interface NDEFReaderLike extends EventTarget {
  scan(options?: { signal?: AbortSignal }): Promise<void>;
}

type NDEFReaderCtor = new () => NDEFReaderLike;

export function getNDEFReaderCtor(): NDEFReaderCtor | null {
  if (typeof window === 'undefined') return null;
  return (window as unknown as { NDEFReader?: NDEFReaderCtor }).NDEFReader ?? null;
}

export interface Spot {
  serial: string;
  name: string;
  claimedAt: number;
  taps: number;
  points: number;
  lastTapAt: number;
}

const SPOTS_KEY = 'kamikaze-nfc-spots-v1';

export const STOMP_WINDOW_MS = 5000;
export const STOMP_POINTS = 100;
export const CHECKIN_POINTS = 10;

export function loadSpots(): Record<string, Spot> {
  if (typeof window === 'undefined') return {};
  try {
    const raw = window.localStorage.getItem(SPOTS_KEY);
    return raw ? (JSON.parse(raw) as Record<string, Spot>) : {};
  } catch {
    return {};
  }
}

export function saveSpots(spots: Record<string, Spot>): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(SPOTS_KEY, JSON.stringify(spots));
  } catch {
    // storage full or private mode: session keeps going in-memory
  }
}

export function claimSpot(serial: string, name: string): Spot {
  const spots = loadSpots();
  const spot: Spot = {
    serial,
    name,
    claimedAt: Date.now(),
    taps: 0,
    points: 0,
    lastTapAt: 0,
  };
  spots[serial] = spot;
  saveSpots(spots);
  return spot;
}

export function tapSpot(serial: string, points: number): Spot | null {
  const spots = loadSpots();
  const spot = spots[serial];
  if (!spot) return null;
  spot.taps += 1;
  spot.points += points;
  spot.lastTapAt = Date.now();
  saveSpots(spots);
  return spot;
}

export function totalSpotPoints(spots: Record<string, Spot>): number {
  return Object.values(spots).reduce((acc, s) => acc + s.points, 0);
}

export function shortSerial(serial: string): string {
  return serial.length > 14 ? `${serial.slice(0, 11)}...` : serial;
}
