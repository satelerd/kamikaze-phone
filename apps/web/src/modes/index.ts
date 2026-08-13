// Data-only mode registry. Mode implementations live in src/app/play/<id>/
// and src/modes/<id>/ and never edit this file's siblings: they only consume
// the shared engines in src/lib/.
import type { ModeDefinition } from '../lib/types';

export const MODES: ModeDefinition[] = [
  {
    id: 'free-ride',
    title: 'Free Ride',
    tagline: 'Open session. The narrator watches every throw and calls it live.',
    emoji: '🌊',
    path: '/play/free-ride',
    requires: ['motion'],
    enhancedBy: ['speech', 'microphone', 'vibration', 'torch'],
  },
  {
    id: 'trick-lab',
    title: 'Trick Lab',
    tagline: 'Slow-mo video + 3D trajectory reconstruction of every trick.',
    emoji: '🎥',
    path: '/play/trick-lab',
    requires: ['motion', 'camera'],
    enhancedBy: ['torch'],
  },
  {
    id: 'grind',
    title: 'Rail Grind',
    tagline: 'Slide the phone down a metal rail. The magnetometer feels the steel.',
    emoji: '🛹',
    path: '/play/grind',
    requires: ['motion', 'magnetometer'],
    enhancedBy: ['vibration', 'torch'],
    lockedHint: 'Needs a magnetometer with a web API (Android Chrome). iOS hides it from the browser.',
  },
  {
    id: 'fridge-surfer',
    title: 'Fridge Surfer',
    tagline: 'Land on a MacBook or any magnetic surface. The compass knows.',
    emoji: '🧲',
    path: '/play/fridge-surfer',
    requires: ['motion', 'magnetometer'],
    enhancedBy: ['vibration'],
    lockedHint: 'Needs a magnetometer with a web API (Android Chrome).',
  },
  {
    id: 'eclipse',
    title: 'Eclipse',
    tagline: 'Throw through darkness. The light sensor times your blackout.',
    emoji: '🌒',
    path: '/play/eclipse',
    requires: ['motion', 'ambientLight'],
    enhancedBy: ['torch'],
    lockedHint: 'Needs the ambient light sensor API (Android Chrome, enable "Generic Sensor" flags if hidden).',
  },
  {
    id: 'scream',
    title: 'Scream Meter',
    tagline: 'Hype scream = score multiplier. The mic hears your commitment.',
    emoji: '📣',
    path: '/play/scream',
    requires: ['motion', 'microphone'],
    enhancedBy: ['speech'],
  },
  {
    id: 'charger-bullseye',
    title: 'Charger Bullseye',
    tagline: 'Toss it onto the wireless charger. Charging = bullseye.',
    emoji: '🔋',
    path: '/play/charger-bullseye',
    requires: ['motion', 'battery'],
    enhancedBy: ['vibration'],
    lockedHint: 'Needs the Battery Status API (Android Chrome).',
  },
  {
    id: 'nfc-spots',
    title: 'NFC Spots',
    tagline: 'Sticker your house with NFC tags. Slam the phone down to claim spots.',
    emoji: '📍',
    path: '/play/nfc-spots',
    requires: ['motion', 'nfc'],
    enhancedBy: ['vibration'],
    lockedHint: 'Needs Web NFC (Android Chrome). On iOS use the QR fallback markers.',
  },
  {
    id: 'hot-potato',
    title: 'Hot Potato',
    tagline: 'Pass it before it blows. Wrap it in a towel. Trust the towel.',
    emoji: '🥔',
    path: '/play/hot-potato',
    requires: ['motion', 'speech'],
    enhancedBy: ['vibration', 'torch'],
  },
  {
    id: 'coop',
    title: 'Co-op Sync',
    tagline: 'Two phones, one trick. Coordination is the score.',
    emoji: '🤝',
    path: '/play/coop',
    requires: ['motion', 'webrtc'],
    enhancedBy: ['camera'],
  },
];

export function getMode(id: string): ModeDefinition | undefined {
  return MODES.find((m) => m.id === id);
}
