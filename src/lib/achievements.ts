// Achievement definitions + unlock helpers. Owned by the minigames agent;
// modes call checkTrickAchievements(result) after recordTrick, and award(id)
// for mode-specific unlocks (grind duration, blackout, bullseye, NFC claims).
import { FXEngine } from './fx';
import { speak } from './speech';
import { getState, unlockAchievement } from './store';
import type { AchievementDef, TrickResult } from './types';

export const ACHIEVEMENTS: AchievementDef[] = [
  // Any mode (trick engine)
  { id: 'first-blood', name: 'First Blood', description: 'Record your very first trick. The phone forgives, once.', emoji: '🩸' },
  { id: 'wipeout-reel', name: 'Wipeout Reel', description: 'Bail one. Everybody eats pavement sometimes.', emoji: '🎬', secret: true },
  { id: 'flapjack-god', name: 'Flapjack God', description: 'Land a Triple Pancake. IHOP wants your autograph.', emoji: '🥞' },
  { id: 'to-the-moon', name: 'To The Moon', description: 'Send it more than 2 meters above your hand.', emoji: '🚀' },
  { id: 's-tier', name: 'S Tier', description: 'Score an S grade on any trick.', emoji: '🏆' },
  { id: 'no-bail-10', name: 'No Bail Streak', description: 'Catch 10 throws in a row. Ice in your veins.', emoji: '🧊' },
  { id: 'hang-ten', name: 'Hang Ten', description: 'Keep it airborne for 1.2 seconds.', emoji: '🤙' },
  { id: 'chopper-license', name: 'Chopper License', description: 'Land any helicopter spin.', emoji: '🚁' },
  { id: 'blender-mode', name: 'Blender Mode', description: 'Throw a corkscrew. Multi-axis mayhem.', emoji: '🌀' },
  { id: 'zen-master', name: 'Zen Master', description: 'Land a Zen Toss. No spin, all soul.', emoji: '🧘' },
  { id: 'hot-hundred', name: 'Hot Hundred', description: 'Log 100 total throws.', emoji: '💯' },
  { id: 'night-rider', name: 'Night Rider', description: 'Land a trick between 11pm and 4am.', emoji: '🌙', secret: true },
  // Trick Lab
  { id: 'auteur', name: 'Auteur', description: 'Record a trick in the Trick Lab.', emoji: '🎥', mode: 'trick-lab' },
  // Rail Grind
  { id: 'first-spark', name: 'First Spark', description: 'Land your first grind on real steel.', emoji: '⚡', mode: 'grind' },
  { id: 'rail-lord', name: 'Rail Lord', description: 'Hold a grind for 2 full seconds.', emoji: '🛹', mode: 'grind' },
  // Fridge Surfer
  { id: 'stuck-the-landing', name: 'Stuck The Landing', description: 'Land on a magnetic surface. The fridge accepts you.', emoji: '🧲', mode: 'fridge-surfer' },
  { id: 'full-metal', name: 'Full Metal', description: 'Stick a landing with a 100 microtesla magnetic slam.', emoji: '🤖', mode: 'fridge-surfer', secret: true },
  // Eclipse
  { id: 'total-eclipse', name: 'Total Eclipse', description: 'Full blackout mid-flight: under 2 lux in a bright room.', emoji: '🌑', mode: 'eclipse' },
  { id: 'shadow-dancer', name: 'Shadow Dancer', description: 'Cut the light by 80 percent during a flight.', emoji: '🕶️', mode: 'eclipse' },
  // Scream Meter
  { id: 'banshee', name: 'Banshee', description: 'Max out the scream meter. The neighbors called.', emoji: '📣', mode: 'scream' },
  { id: 'heard-the-whoosh', name: 'Heard The Whoosh', description: 'The mic caught your phone slicing the air.', emoji: '💨', mode: 'scream' },
  // Charger Bullseye
  { id: 'dead-center', name: 'Dead Center', description: 'Land on the wireless charger. BULLSEYE.', emoji: '🎯', mode: 'charger-bullseye' },
  { id: 'triple-juice', name: 'Triple Juice', description: 'Three bullseyes in a row. Fully charged ego.', emoji: '🔋', mode: 'charger-bullseye' },
  // NFC Spots
  { id: 'tag-youre-it', name: "Tag, You're It", description: 'Claim your first NFC spot.', emoji: '📍', mode: 'nfc-spots' },
  { id: 'spot-mogul', name: 'Spot Mogul', description: 'Claim 5 spots. Local legend status.', emoji: '🗺️', mode: 'nfc-spots' },
  { id: 'stomp-the-yard', name: 'Stomp The Yard', description: 'Land the phone right on a claimed tag.', emoji: '🦶', mode: 'nfc-spots' },
  // Hot Potato
  { id: 'towel-believer', name: 'Towel Believer', description: 'Play Hot Potato after the towel safety briefing. Trust the towel.', emoji: '🧣', mode: 'hot-potato' },
  { id: 'last-spud-standing', name: 'Last Spud Standing', description: 'Win a Hot Potato elimination round.', emoji: '🥔', mode: 'hot-potato' },
  // Co-op
  { id: 'sync-souls', name: 'Sync Souls', description: 'Hit 90 percent sync with your co-op partner.', emoji: '🤝', mode: 'coop' },
];

export function getAchievement(id: string): AchievementDef | undefined {
  return ACHIEVEMENTS.find((a) => a.id === id);
}

/** FX + narrator celebration for freshly unlocked ids. */
function celebrate(ids: string[]): void {
  if (!ids.length) return;
  for (const id of ids) FXEngine.handle({ type: 'achievement', id });
  const names = ids.map((id) => getAchievement(id)?.name ?? id).join(', and ');
  speak(`Badge unlocked: ${names}. Righteous!`, { style: 'surfer' });
}

/**
 * Unlock a specific achievement (mode-specific conditions the mode itself
 * verifies, e.g. a 2 second grind). Returns true only when newly unlocked;
 * repeat calls are silent no-ops.
 */
export function award(id: string): boolean {
  if (!unlockAchievement(id)) return false;
  celebrate([id]);
  return true;
}

/**
 * Evaluate every trick-based achievement for a fresh TrickResult.
 * Call after recordTrick(result) so streaks and totals include it.
 * Fires FX + narration for new unlocks and returns the newly unlocked ids.
 */
export function checkTrickAchievements(result: TrickResult): string[] {
  const s = getState();
  const alreadyRecorded =
    s.history.length > 0 && s.history[0].id === result.id && s.history[0].at === result.at;
  const history = alreadyRecorded ? s.history : [result, ...s.history];
  const caught = result.grade !== 'BAIL';
  const hour = new Date(result.at).getHours();

  let streak = 0;
  for (const h of history) {
    if (h.grade === 'BAIL') break;
    streak++;
  }
  const totalThrows = Math.max(s.totalThrows, history.length);

  const hits: Record<string, boolean> = {
    'first-blood': true,
    'wipeout-reel': !caught,
    'flapjack-god': caught && result.trickId === 'pancake-triple',
    'to-the-moon': result.features.height >= 2,
    's-tier': result.grade === 'S',
    'no-bail-10': streak >= 10,
    'hang-ten': result.features.airtime >= 1.2,
    'chopper-license': caught && result.trickId.startsWith('helicopter'),
    'blender-mode': result.trickId === 'corkscrew',
    'zen-master': caught && result.trickId === 'zen-toss',
    'hot-hundred': totalThrows >= 100,
    'night-rider': hour >= 23 || hour < 4,
    auteur: result.mode === 'trick-lab',
  };

  const newly: string[] = [];
  for (const [id, hit] of Object.entries(hits)) {
    if (hit && unlockAchievement(id)) newly.push(id);
  }
  celebrate(newly);
  return newly;
}
