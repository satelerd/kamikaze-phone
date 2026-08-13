'use client';

// Two phones, one trick: pairing (host QR / join code), NTP clock sync,
// synchronized countdown, simultaneous throws, coordination scoring.
import { useCallback, useEffect, useRef, useState } from 'react';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import { CoopPeer, makeJoinQR, normalizeRoomCode } from '@/lib/peer';
import type { CoopMessage, PeerStatus } from '@/lib/peer';
import { classifyThrow } from '@/lib/physics';
import { SensorEngine } from '@/lib/sensors';
import { recordTrick } from '@/lib/store';
import Countdown from './Countdown';
import SyncResult from './SyncResult';
import TrickCard from './TrickCard';
import {
  COUNTDOWN_LEAD_MS,
  celebrateSync,
  computeSync,
  landEpochOf,
  launchEpochOf,
  riderFromResult,
  riderFromThrowMessage,
  throwMessageOf,
} from './sync';
import type { RiderThrow, SyncBreakdown } from './sync';
import { useThrowCapture } from './useThrowCapture';
import { useWakeLock } from './useWakeLock';

type Round =
  | { phase: 'lobby' }
  | { phase: 'countdown'; startAt: number }
  | { phase: 'throw' }
  | { phase: 'result'; bd: SyncBreakdown; best: number; isNewBest: boolean };

function formatOffset(ms: number): string {
  const r = Math.round(ms);
  return `${r >= 0 ? '+' : ''}${r}ms`;
}

function StatusChip({ label, done, text }: { label: string; done: boolean; text: string }) {
  return (
    <div
      className={`rounded-xl border px-3 py-2 text-left ${
        done ? 'border-emerald-400/60 bg-emerald-400/10' : 'border-zinc-700 bg-zinc-950/60'
      }`}
    >
      <div className="truncate text-[10px] uppercase tracking-widest text-zinc-400">{label}</div>
      <div className={`mt-0.5 truncate text-sm font-bold ${done ? 'text-emerald-300' : 'text-zinc-400'}`}>
        {done ? `${text} ✅` : text}
      </div>
    </div>
  );
}

export default function LinkedMode({
  playerName,
  initialJoinCode,
}: {
  playerName: string;
  initialJoinCode?: string;
}) {
  const peerRef = useRef<CoopPeer | null>(null);
  const prevConnectedRef = useRef(false);
  const [status, setStatus] = useState<PeerStatus>({ s: 'idle' });
  const [qr, setQr] = useState<string | null>(null);
  const [codeInput, setCodeInput] = useState(initialJoinCode ?? '');
  const [joinOpen, setJoinOpen] = useState(Boolean(initialJoinCode));
  const [banner, setBanner] = useState<string | null>(null);
  const [motionOk, setMotionOk] = useState<boolean | null>(null);
  const [clock, setClock] = useState<{ offset: number; rtt: number } | null>(null);
  const [clockBusy, setClockBusy] = useState(false);
  const [round, setRound] = useState<Round>({ phase: 'lobby' });
  const roundRef = useRef(round);
  roundRef.current = round;
  const [me, setMe] = useState<RiderThrow | null>(null);
  const [them, setThem] = useState<RiderThrow | null>(null);

  useWakeLock(status.s === 'connected');

  const { arm, disarm } = useThrowCapture((rec) => {
    const result = classifyThrow(rec, 'coop');
    recordTrick(result);
    FXEngine.handle({ type: 'trick', result });
    const mine = riderFromResult(result, launchEpochOf(rec), landEpochOf(rec), playerName);
    setMe(mine);
    peerRef.current?.send(throwMessageOf(mine));
  });

  const runClockSync = useCallback(async (p: CoopPeer) => {
    setClockBusy(true);
    try {
      const r = await p.measureClockOffset();
      setClock(r);
    } catch {
      setClock(null);
    } finally {
      setClockBusy(false);
    }
  }, []);

  const teardown = useCallback(
    (reason: string | null) => {
      disarm();
      peerRef.current?.close();
      peerRef.current = null;
      prevConnectedRef.current = false;
      setStatus({ s: 'idle' });
      setQr(null);
      setClock(null);
      setClockBusy(false);
      setRound({ phase: 'lobby' });
      setMe(null);
      setThem(null);
      if (reason) setBanner(reason);
    },
    [disarm],
  );

  const beginCountdown = useCallback(
    (startAtLocal: number) => {
      disarm();
      setMe(null);
      setThem(null);
      setBanner(null);
      setRound({ phase: 'countdown', startAt: startAtLocal });
    },
    [disarm],
  );

  const handleMessage = useCallback(
    (p: CoopPeer, m: CoopMessage) => {
      if (m.t === 'countdown') {
        beginCountdown(p.toLocalTime(m.startAt));
      } else if (m.t === 'throw') {
        setThem(riderFromThrowMessage(m, (t) => p.toLocalTime(t), p.remoteName ?? 'Partner'));
      }
    },
    [beginCountdown],
  );

  const startPeer = useCallback(
    async (role: 'host' | 'join', code?: string) => {
      setBanner(null);
      // user gesture: unlock audio + motion sensors before anything async
      AudioBus.ensure();
      const engine = SensorEngine.get();
      const ok = await engine.requestPermission();
      setMotionOk(ok);
      if (ok) engine.start();
      FXEngine.handle({ type: 'ui-start' });

      peerRef.current?.close();
      prevConnectedRef.current = false;
      const p = new CoopPeer(playerName);
      peerRef.current = p;
      setStatus(p.status);
      p.onStatus((st) => {
        setStatus(st);
        const isConn = st.s === 'connected';
        if (isConn && !prevConnectedRef.current) void runClockSync(p);
        prevConnectedRef.current = isConn;
        if (st.s === 'disconnected') {
          teardown(`${st.reason} Pair up again when you are ready.`);
        }
      });
      p.onMessage((m) => handleMessage(p, m));
      try {
        if (role === 'host') await p.host();
        else await p.join(code ?? '');
      } catch {
        // already surfaced through the 'error' status
      }
    },
    [handleMessage, playerName, runClockSync, teardown],
  );

  // Render the QR invite once the room is claimed.
  useEffect(() => {
    if (status.s !== 'waiting') {
      setQr(null);
      return;
    }
    let alive = true;
    makeJoinQR(status.code)
      .then((url) => {
        if (alive) setQr(url);
      })
      .catch(() => undefined);
    return () => {
      alive = false;
    };
  }, [status]);

  // Both throws in: score the round exactly once.
  useEffect(() => {
    if (!me || !them) return;
    if (roundRef.current.phase === 'result') return;
    const bd = computeSync(me, them, 'linked');
    const { best, isNewBest } = celebrateSync(bd);
    setRound({ phase: 'result', bd, best, isNewBest });
  }, [me, them]);

  // Leaving the page = leaving the session.
  useEffect(
    () => () => {
      peerRef.current?.close();
      peerRef.current = null;
    },
    [],
  );

  const dropCount = useCallback(() => {
    const p = peerRef.current;
    if (!p) return;
    const startAt = Date.now() + COUNTDOWN_LEAD_MS;
    p.send({ t: 'countdown', startAt });
    beginCountdown(startAt);
  }, [beginCountdown]);

  const onGo = useCallback(() => {
    FXEngine.handle({ type: 'ui-start' });
    arm();
    setRound({ phase: 'throw' });
  }, [arm]);

  const cancelRound = useCallback(() => {
    disarm();
    setMe(null);
    setThem(null);
    setRound({ phase: 'lobby' });
  }, [disarm]);

  const isHost = peerRef.current?.role === 'host';
  const peerName =
    (status.s === 'connected' && status.peerName) || peerRef.current?.remoteName || 'Partner';

  // ---------------------------------------------------------------- pairing
  if (status.s === 'idle') {
    return (
      <div className="space-y-4">
        {banner && (
          <div className="rounded-2xl border border-amber-400/50 bg-amber-400/10 p-4 text-sm text-amber-200">
            ⚡ {banner}
          </div>
        )}
        {!joinOpen ? (
          <>
            <button
              onClick={() => void startPeer('host')}
              className="w-full rounded-2xl bg-amber-400 px-4 py-5 text-lg font-black text-zinc-950 active:scale-95"
            >
              HOST A ROOM 📡
              <span className="mt-1 block text-xs font-semibold opacity-80">
                Get a code + QR for your partner
              </span>
            </button>
            <button
              onClick={() => setJoinOpen(true)}
              className="w-full rounded-2xl border border-zinc-700 bg-zinc-900 px-4 py-5 text-lg font-black active:scale-95"
            >
              JOIN A ROOM 🎟️
              <span className="mt-1 block text-xs font-semibold text-zinc-400">
                Scan the QR or punch in the code
              </span>
            </button>
            <p className="text-center text-xs text-zinc-500">
              Peer-to-peer over the free PeerJS cloud. No accounts, no backend, pure stoke.
            </p>
          </>
        ) : (
          <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-4">
            <label className="text-sm text-zinc-400">Room code</label>
            <input
              value={codeInput}
              onChange={(e) => setCodeInput(e.target.value)}
              placeholder="kmkz-abcd"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              className="mt-1 w-full rounded-xl border border-zinc-700 bg-zinc-950 px-4 py-3 font-mono text-lg outline-none focus:border-amber-400"
            />
            <button
              onClick={() => void startPeer('join', codeInput)}
              disabled={!normalizeRoomCode(codeInput)}
              className="mt-3 w-full rounded-xl bg-amber-400 px-4 py-3 font-black text-zinc-950 active:scale-95 disabled:opacity-40"
            >
              DROP IN 🤙
            </button>
            <button
              onClick={() => setJoinOpen(false)}
              className="mt-2 w-full rounded-xl border border-zinc-700 px-4 py-2 text-sm text-zinc-300"
            >
              Back
            </button>
          </div>
        )}
      </div>
    );
  }

  if (status.s === 'starting') {
    return (
      <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-6 text-center">
        <p className="animate-pulse text-sm text-zinc-300">Dialing the signal tower... 🛰️</p>
        <button
          onClick={() => teardown(null)}
          className="mt-4 rounded-xl border border-zinc-700 px-4 py-2 text-sm text-zinc-300"
        >
          Cancel
        </button>
      </div>
    );
  }

  if (status.s === 'waiting') {
    return (
      <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-5 text-center">
        <div className="text-xs uppercase tracking-[0.3em] text-zinc-400">Room code</div>
        <div className="mt-1 font-mono text-4xl font-black text-amber-400">{status.code}</div>
        {qr ? (
          // eslint-disable-next-line @next/next/no-img-element -- QR is a local data URL
          <img
            src={qr}
            alt={`QR invite for room ${status.code}`}
            className="mx-auto mt-4 w-56 rounded-xl bg-white p-2"
          />
        ) : (
          <div className="mt-4 text-sm text-zinc-500">Rendering QR...</div>
        )}
        <p className="mt-4 text-sm text-zinc-400">
          Partner scans the QR, or opens /play/coop and punches in the code.
        </p>
        <p className="mt-2 animate-pulse text-sm text-amber-200">
          Waiting for your partner to drop in... 📡
        </p>
        <button
          onClick={() => teardown(null)}
          className="mt-4 rounded-xl border border-zinc-700 px-4 py-2 text-sm text-zinc-300"
        >
          Cancel
        </button>
      </div>
    );
  }

  if (status.s === 'connecting') {
    return (
      <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-6 text-center">
        <p className="animate-pulse text-sm text-zinc-300">
          Dropping into <span className="font-mono font-bold text-amber-400">{status.code}</span>... 🌀
        </p>
        <button
          onClick={() => teardown(null)}
          className="mt-4 rounded-xl border border-zinc-700 px-4 py-2 text-sm text-zinc-300"
        >
          Cancel
        </button>
      </div>
    );
  }

  if (status.s === 'error' || status.s === 'disconnected') {
    const message = status.s === 'error' ? status.message : status.reason;
    return (
      <div className="rounded-2xl border border-red-500/50 bg-red-500/10 p-4">
        <div className="font-black text-red-300">Wipeout 🌊</div>
        <p className="mt-1 text-sm text-red-200">{message}</p>
        <button
          onClick={() => teardown(null)}
          className="mt-3 w-full rounded-xl border border-zinc-700 px-4 py-2 text-sm text-zinc-200"
        >
          Back to pairing
        </button>
      </div>
    );
  }

  // ---------------------------------------------------------------- connected
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between rounded-2xl border border-zinc-700 bg-zinc-900 px-4 py-3">
        <div className="min-w-0">
          <div className="truncate text-sm font-black">🤝 Linked with {peerName}</div>
          <div className="text-xs text-zinc-500">room {status.code}</div>
        </div>
        <button
          onClick={() => teardown(null)}
          className="shrink-0 rounded-lg border border-zinc-700 px-3 py-1.5 text-xs text-zinc-300"
        >
          Unpair
        </button>
      </div>

      <div className="flex items-center justify-between rounded-xl border border-zinc-800 bg-zinc-950/60 px-3 py-2 text-xs text-zinc-400">
        {clockBusy ? (
          <span className="animate-pulse">Calibrating clocks... 🛰️</span>
        ) : clock ? (
          <span>
            Clocks locked 🛰️ offset {formatOffset(clock.offset)} · ping {clock.rtt}ms
          </span>
        ) : (
          <span>Clock sync failed. Countdown may drift.</span>
        )}
        {!clockBusy && (
          <button
            onClick={() => {
              const p = peerRef.current;
              if (p) void runClockSync(p);
            }}
            className="text-amber-400 underline underline-offset-2"
          >
            re-sync
          </button>
        )}
      </div>

      {motionOk === false && (
        <div className="rounded-xl border border-amber-400/40 bg-amber-400/10 px-3 py-2 text-xs text-amber-200">
          Motion sensors are off. Pairing works but throws will not register. Check browser
          permissions.
        </div>
      )}

      {round.phase === 'lobby' &&
        (isHost ? (
          <button
            onClick={dropCount}
            disabled={clockBusy}
            className="w-full rounded-2xl bg-amber-400 px-4 py-5 text-xl font-black text-zinc-950 active:scale-95 disabled:opacity-40"
          >
            DROP THE COUNT 🚀
            <span className="mt-1 block text-xs font-semibold opacity-80">
              Both phones count down together. Throw on zero.
            </span>
          </button>
        ) : (
          <div className="rounded-2xl border border-zinc-700 bg-zinc-900 p-6 text-center text-sm text-zinc-400">
            Your host drops the count. Stay loose. 🌊
          </div>
        ))}

      {round.phase === 'countdown' && (
        <Countdown
          startAt={round.startAt}
          onGo={onGo}
          subtitle="Synced countdown"
          hint="Both phones. Same beat. SEND IT on zero."
        />
      )}

      {round.phase === 'throw' && (
        <div className="rounded-2xl border border-amber-400/60 bg-zinc-900 p-6 text-center">
          <div className="text-5xl font-black text-amber-400">SEND IT! 🚀</div>
          <p className="mt-2 text-sm text-zinc-400">Throw NOW. Land it clean.</p>
          <div className="mt-5 grid grid-cols-2 gap-3 text-sm">
            <StatusChip label="You" done={Boolean(me)} text={me ? me.trickName : 'In the air...'} />
            <StatusChip
              label={peerName}
              done={Boolean(them)}
              text={them ? them.trickName : 'Waiting...'}
            />
          </div>
          {me && !them && (
            <p className="mt-4 animate-pulse text-sm text-zinc-400">
              {`Waiting for ${peerName}'s throw...`}
            </p>
          )}
          <button
            onClick={cancelRound}
            className="mt-4 rounded-xl border border-zinc-700 px-4 py-2 text-sm text-zinc-300"
          >
            Cancel round
          </button>
        </div>
      )}

      {round.phase === 'result' && me && them && (
        <>
          <div className="grid grid-cols-2 gap-3">
            <TrickCard rider={me} label="You" />
            <TrickCard rider={them} label={peerName} />
          </div>
          <SyncResult bd={round.bd} best={round.best} isNewBest={round.isNewBest}>
            {isHost ? (
              <button
                onClick={dropCount}
                className="w-full rounded-xl bg-amber-400 px-4 py-3 font-black text-zinc-950 active:scale-95"
              >
                REMATCH 🔁
              </button>
            ) : (
              <p className="text-center text-sm text-zinc-400">
                Your host calls the rematch. Stay stoked. 🤙
              </p>
            )}
          </SyncResult>
        </>
      )}
    </div>
  );
}
