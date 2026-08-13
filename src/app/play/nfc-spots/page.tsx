'use client';

// NFC Spots: sticker your world with NFC tags, name and claim them like skate
// spots, then land the phone on a claimed tag and re-scan to bank the stomp.
// Web NFC scan must start from a user gesture; NotAllowedError is handled.
import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { award } from '@/lib/achievements';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import { ThrowTracker, type ThrowRecord } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { speak } from '@/lib/speech';
import {
  CHECKIN_POINTS, claimSpot, getNDEFReaderCtor, loadSpots, shortSerial, STOMP_POINTS,
  STOMP_WINDOW_MS, tapSpot, totalSpotPoints, type NDEFReadingEventLike, type Spot,
} from '@/modes/nfc-spots/logic';
import { nextSimSerial, simulateStompThrow } from '@/modes/nfc-spots/sim';

function useWakeLock(active: boolean): void {
  useEffect(() => {
    if (!active) return;
    let sentinel: WakeLockSentinel | null = null;
    let cancelled = false;
    const request = async () => {
      try {
        if ('wakeLock' in navigator) {
          sentinel = await navigator.wakeLock.request('screen');
          if (cancelled) await sentinel.release();
        }
      } catch {
        // wake lock unavailable
      }
    };
    void request();
    const onVis = () => {
      if (document.visibilityState === 'visible') void request();
    };
    document.addEventListener('visibilitychange', onVis);
    return () => {
      cancelled = true;
      document.removeEventListener('visibilitychange', onVis);
      void sentinel?.release().catch(() => {});
    };
  }, [active]);
}

const SPOT_NAME_IDEAS = ['Kitchen Ledge', 'Couch Gap', 'Fridge North Face', 'Desk Drop Zone'];

export default function NfcSpotsPage() {
  const [scanning, setScanning] = useState(false);
  const [scanError, setScanError] = useState<string | null>(null);
  const [spots, setSpots] = useState<Record<string, Spot>>({});
  const [pendingSerial, setPendingSerial] = useState<string | null>(null);
  const [spotName, setSpotName] = useState('');
  const [lastEvent, setLastEvent] = useState('Stick NFC tags around the house. Scan one to claim it as a spot.');
  const [motionArmed, setMotionArmed] = useState(false);
  const [simActive, setSimActive] = useState(false);

  const trackerRef = useRef<ThrowTracker | null>(null);
  const imuUnsubRef = useRef<(() => void) | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const cancelSimRef = useRef<(() => void) | null>(null);
  const lastLandWallRef = useRef(-Infinity);
  const simStompSerialRef = useRef<string | null>(null);
  const handleSerialRef = useRef<(serial: string) => void>(() => {});

  useWakeLock(scanning || motionArmed);

  useEffect(() => {
    setSpots(loadSpots());
    return () => {
      abortRef.current?.abort();
      imuUnsubRef.current?.();
      imuUnsubRef.current = null;
      cancelSimRef.current?.();
    };
  }, []);

  const handleSerial = (serial: string) => {
    const all = loadSpots();
    const known = all[serial];
    if (!known) {
      setPendingSerial(serial);
      setSpotName('');
      setLastEvent(`Fresh tag found (${shortSerial(serial)}). Name it and claim it!`);
      FXEngine.handle({ type: 'ui-select' });
      return;
    }
    const sinceLanding = performance.now() - lastLandWallRef.current;
    if (sinceLanding <= STOMP_WINDOW_MS) {
      tapSpot(serial, STOMP_POINTS);
      setLastEvent(`STOMP! Landed right on ${known.name}. +${STOMP_POINTS} points!`);
      award('stomp-the-yard');
      FXEngine.handle({ type: 'catch', clean: true, impactG: 20 });
      speak(`Stomped ${known.name}! That tag felt it!`, { style: 'surfer' });
    } else {
      tapSpot(serial, CHECKIN_POINTS);
      setLastEvent(
        `Checked in at ${known.name}. +${CHECKIN_POINTS}. Throw the phone at it for the big points!`,
      );
      FXEngine.handle({ type: 'ui-select' });
    }
    setSpots(loadSpots());
  };
  handleSerialRef.current = handleSerial;

  const startScan = async () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    const Ctor = getNDEFReaderCtor();
    if (!Ctor) {
      setScanError('No Web NFC on this rig. Android Chrome only. See the QR fallback below.');
      return;
    }
    try {
      const reader = new Ctor();
      const ac = new AbortController();
      abortRef.current?.abort();
      abortRef.current = ac;
      reader.addEventListener('reading', ((e: Event) => {
        const ev = e as NDEFReadingEventLike;
        if (ev.serialNumber) handleSerialRef.current(ev.serialNumber);
      }) as EventListener);
      await reader.scan({ signal: ac.signal });
      setScanning(true);
      setScanError(null);
      setLastEvent('Scanner is hot. Touch a tag!');
    } catch (err) {
      const name = err instanceof DOMException ? err.name : '';
      setScanError(
        name === 'NotAllowedError'
          ? 'NFC permission denied. Flip it on in site settings and try again.'
          : name === 'NotSupportedError'
            ? 'NFC hardware says no. Try the QR fallback below.'
            : 'NFC scan failed to start. Give it another go.',
      );
    }
  };

  const ensureTracker = () => {
    if (!trackerRef.current) {
      trackerRef.current = new ThrowTracker(
        (rec: ThrowRecord) => {
          lastLandWallRef.current = performance.now() - rec.settleMs;
          setLastEvent('Landed! Scan the tag under it within 5 seconds to bank the stomp.');
          if (simStompSerialRef.current) {
            const serial = simStompSerialRef.current;
            simStompSerialRef.current = null;
            setTimeout(() => handleSerialRef.current(serial), 500);
          }
        },
        (e) => FXEngine.handle(e),
      );
    }
    return trackerRef.current;
  };

  const armMotion = async () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-select' });
    const ok = await SensorEngine.get().requestPermission();
    if (!ok) {
      setLastEvent('Motion permission denied. Claims still work; stomps need sensors.');
      return;
    }
    SensorEngine.get().start();
    ensureTracker();
    if (!imuUnsubRef.current) {
      imuUnsubRef.current = SensorEngine.get().onIMU((s) => trackerRef.current?.feed(s));
    }
    setMotionArmed(true);
    setLastEvent('Throw sensors armed. Land on a claimed tag and re-scan it fast.');
  };

  const claim = () => {
    if (!pendingSerial) return;
    const name = spotName.trim() || SPOT_NAME_IDEAS[Math.floor(Math.random() * SPOT_NAME_IDEAS.length)];
    claimSpot(pendingSerial, name);
    setSpots(loadSpots());
    setPendingSerial(null);
    setSpotName('');
    const count = Object.keys(loadSpots()).length;
    FXEngine.handle({ type: 'ui-start' });
    award('tag-youre-it');
    if (count >= 5) award('spot-mogul');
    setLastEvent(`${name} claimed. ${count} spot${count === 1 ? '' : 's'} in your empire.`);
    speak(`${name} is yours now. Defend it!`, { style: 'surfer' });
  };

  const simScan = () => {
    AudioBus.ensure();
    handleSerial(nextSimSerial());
  };

  const simStomp = () => {
    AudioBus.ensure();
    FXEngine.handle({ type: 'ui-start' });
    const claimed = Object.values(loadSpots());
    if (!claimed.length) {
      setLastEvent('No claimed spots yet. Simulate a tag scan and claim it first.');
      return;
    }
    cancelSimRef.current?.();
    ensureTracker();
    simStompSerialRef.current = claimed[Math.floor(Math.random() * claimed.length)].serial;
    setSimActive(true);
    setLastEvent('Simulated throw incoming...');
    cancelSimRef.current = simulateStompThrow(
      (s) => trackerRef.current?.feed(s),
      () => setSimActive(false),
    );
  };

  const spotList = Object.values(spots).sort((a, b) => b.points - a.points);
  const totalPoints = totalSpotPoints(spots);

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-10">
      <Link href="/" className="text-sm text-zinc-400">
        ← Back to the lineup
      </Link>
      <h1 className="mt-2 text-3xl font-black">NFC Spots 📍</h1>
      <p className="mt-1 text-sm text-zinc-400">
        Claim tags like skate spots. Land the phone on a claimed tag and re-scan it within 5
        seconds for the stomp bonus.
      </p>

      <div className="mt-4 flex items-center gap-2">
        <span
          className={`rounded-full px-3 py-1 text-xs font-bold ${
            scanning ? 'bg-emerald-400/20 text-emerald-300' : 'bg-zinc-800 text-zinc-400'
          }`}
        >
          {scanning ? '📡 scanning' : 'scanner off'}
        </span>
        <span
          className={`rounded-full px-3 py-1 text-xs font-bold ${
            motionArmed ? 'bg-emerald-400/20 text-emerald-300' : 'bg-zinc-800 text-zinc-400'
          }`}
        >
          {motionArmed ? '🤸 throws armed' : 'throws off'}
        </span>
        <span className="rounded-full bg-zinc-800 px-3 py-1 text-xs font-bold text-amber-400">
          {totalPoints} pts
        </span>
      </div>

      {scanError && (
        <div className="mt-4 rounded-2xl border border-amber-400/40 bg-amber-400/10 p-3 text-xs text-amber-200">
          {scanError}
        </div>
      )}

      <p className="mt-4 min-h-10 text-sm text-zinc-300">{lastEvent}</p>

      {pendingSerial && (
        <section className="mt-4 rounded-2xl border border-amber-400/60 bg-amber-400/10 p-4">
          <div className="text-sm font-bold text-amber-200">
            New spot: {shortSerial(pendingSerial)}
          </div>
          <input
            value={spotName}
            onChange={(e) => setSpotName(e.target.value)}
            placeholder={`e.g. ${SPOT_NAME_IDEAS[0]}`}
            className="mt-2 w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 outline-none focus:border-amber-400"
          />
          <div className="mt-3 grid grid-cols-2 gap-3">
            <button
              onClick={claim}
              className="rounded-xl bg-amber-400 px-4 py-3 font-black text-zinc-950 active:scale-95"
            >
              CLAIM IT 📍
            </button>
            <button
              onClick={() => setPendingSerial(null)}
              className="rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold active:scale-95"
            >
              Skip
            </button>
          </div>
        </section>
      )}

      <div className="mt-4 space-y-3">
        <button
          onClick={startScan}
          className="w-full rounded-xl bg-amber-400 px-4 py-4 text-lg font-black text-zinc-950 active:scale-95"
        >
          {scanning ? 'SCANNER IS HOT 📡' : 'START SCANNING 📡'}
        </button>
        <button
          onClick={armMotion}
          className="w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold active:scale-95"
        >
          {motionArmed ? 'Throw sensors: ON 🤸' : 'Arm throw sensors 🤸'}
        </button>
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={simScan}
            className="rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 text-sm font-semibold active:scale-95"
          >
            Simulate tag scan 🖥️
          </button>
          <button
            onClick={simStomp}
            disabled={simActive}
            className="rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 text-sm font-semibold disabled:opacity-40 active:scale-95"
          >
            Simulate throw + stomp 🖥️
          </button>
        </div>
      </div>

      {spotList.length > 0 && (
        <section className="mt-6">
          <h2 className="text-sm font-bold text-zinc-300">
            Your spots ({spotList.length})
          </h2>
          <div className="mt-2 space-y-2">
            {spotList.map((s) => (
              <div
                key={s.serial}
                className="flex items-center justify-between rounded-2xl border border-zinc-700 bg-zinc-900 p-3"
              >
                <div>
                  <div className="font-bold">📍 {s.name}</div>
                  <div className="text-xs text-zinc-500">
                    {shortSerial(s.serial)} · {s.taps} tap{s.taps === 1 ? '' : 's'} · claimed{' '}
                    {new Date(s.claimedAt).toLocaleDateString()}
                  </div>
                </div>
                <div className="text-lg font-black text-amber-400">{s.points}</div>
              </div>
            ))}
          </div>
        </section>
      )}

      <p className="mt-6 text-xs text-zinc-600">
        iPhone rider? Web NFC is Android-only, so print QR stickers as spot markers instead: scan
        with the camera, then tap the link. Same ritual, different radio.
      </p>
    </main>
  );
}
