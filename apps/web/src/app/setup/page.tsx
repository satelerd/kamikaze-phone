'use client';

// Onboarding: pick your device (Pixel 9 first-class), grant permissions,
// see the live capability report. Detection always wins over the preset.
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  CAPABILITY_LABELS, DEVICE_PRESETS, detectCapabilities, probeTorch,
} from '@/lib/capabilities';
import { SensorEngine } from '@/lib/sensors';
import { AudioBus } from '@/lib/audio';
import { FXEngine } from '@/lib/fx';
import { getState, updateProfile } from '@/lib/store';
import type { CapabilityKey, CapabilityReport, DevicePresetId } from '@/lib/types';

const STATE_BADGE: Record<string, string> = {
  yes: '✅',
  'needs-permission': '🔐',
  unknown: '❓',
  no: '⛔',
};

export default function SetupPage() {
  const router = useRouter();
  const [name, setName] = useState('');
  const [device, setDevice] = useState<DevicePresetId | null>(null);
  const [caps, setCaps] = useState<CapabilityReport | null>(null);
  const [motionGranted, setMotionGranted] = useState<boolean | null>(null);
  const [torchReal, setTorchReal] = useState<boolean | null>(null);

  useEffect(() => {
    const s = getState();
    setName(s.profile.playerName);
    setDevice(s.profile.device);
    setCaps(detectCapabilities());
  }, []);

  const grantMotion = async () => {
    AudioBus.ensure();
    const ok = await SensorEngine.get().requestPermission();
    setMotionGranted(ok);
    if (ok) SensorEngine.get().start();
    setCaps(detectCapabilities());
    FXEngine.handle({ type: 'ui-select' });
  };

  const testTorch = async () => {
    const ok = await probeTorch();
    setTorchReal(ok);
  };

  const done = () => {
    updateProfile({ playerName: name || 'Rider', device, setupDone: true });
    FXEngine.handle({ type: 'ui-start' });
    router.push('/');
  };

  return (
    <main className="mx-auto min-h-screen max-w-xl px-4 pb-24 pt-10">
      <h1 className="text-3xl font-black">Setup your rig 🛠️</h1>

      <section className="mt-6">
        <label className="text-sm text-zinc-400">Rider name</label>
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. Max"
          className="mt-1 w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 outline-none focus:border-amber-400"
        />
      </section>

      <section className="mt-6">
        <p className="text-sm text-zinc-400">What phone are you sacrificing today?</p>
        <div className="mt-2 grid grid-cols-2 gap-3">
          {DEVICE_PRESETS.map((p) => (
            <button
              key={p.id}
              onClick={() => setDevice(p.id)}
              className={`rounded-xl border p-3 text-left ${
                device === p.id ? 'border-amber-400 bg-amber-400/10' : 'border-zinc-700 bg-zinc-900'
              }`}
            >
              <div className="font-bold">{p.label}</div>
              <div className="mt-1 text-xs text-zinc-400">{p.blurb}</div>
            </button>
          ))}
        </div>
      </section>

      <section className="mt-6 space-y-3">
        <button
          onClick={grantMotion}
          className="w-full rounded-xl bg-amber-400 px-4 py-3 font-bold text-zinc-950 active:scale-95"
        >
          {motionGranted === null
            ? 'Enable motion sensors'
            : motionGranted
              ? 'Motion sensors: ON ✅'
              : 'Motion denied. Check browser settings ⚠️'}
        </button>
        <button
          onClick={testTorch}
          className="w-full rounded-xl border border-zinc-700 bg-zinc-900 px-4 py-3 font-semibold active:scale-95"
        >
          {torchReal === null ? 'Test flashlight control' : torchReal ? 'Torch: controllable ✅' : 'No torch API. Screen-flash mode 💡'}
        </button>
      </section>

      {caps && (
        <section className="mt-6 rounded-xl border border-zinc-800 bg-zinc-900/60 p-4">
          <p className="mb-2 text-sm font-bold text-zinc-300">Live capability report</p>
          <ul className="grid grid-cols-1 gap-1 text-sm text-zinc-400 sm:grid-cols-2">
            {(Object.keys(CAPABILITY_LABELS) as CapabilityKey[]).map((k) => (
              <li key={k}>
                {STATE_BADGE[caps[k]]} {CAPABILITY_LABELS[k]}
              </li>
            ))}
          </ul>
          <p className="mt-3 text-xs text-zinc-500">
            Locked modes stay visible and explain what sensor they need. Detection beats presets.
          </p>
        </section>
      )}

      <button
        onClick={done}
        disabled={!device}
        className="mt-8 w-full rounded-xl bg-emerald-400 px-4 py-4 text-lg font-black text-zinc-950 disabled:opacity-40"
      >
        LET&apos;S RIDE 🤙
      </button>
    </main>
  );
}
