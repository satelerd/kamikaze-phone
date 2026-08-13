// Narration line pools for the Hot Potato caller voice.
// Kept as data so the game loop stays readable. {n} = player name, {r} = round.

function pick(pool: readonly string[]): string {
  return pool[Math.floor(Math.random() * pool.length)];
}

const CATCH: readonly string[] = [
  '{n} has it!',
  '{n}, hot hands, pass it!',
  'Coming in hot, {n}!',
  '{n} is holding the spud!',
  'Move it, {n}, move it!',
  'Tick tick tick, {n}!',
  'All yours, {n}! Get rid of it!',
];

const DROP: readonly string[] = [
  'Butterfingers, {n}! Still your potato!',
  '{n} dropped it! The spud stays put!',
  'Whoa {n}, sketchy hands! Keep it!',
  'Fumble city! {n} is stuck with it!',
  'That was ugly, {n}. Still yours!',
];

const AIRBORNE: readonly string[] = [
  "It's airborne!",
  'Up it goes!',
  'Full send!',
  'Spud in flight!',
  'Look at it fly!',
];

const BOOM: readonly string[] = [
  'Boom! {n} is cooked!',
  '{n} got roasted! Total wipeout!',
  'Kaboom! {n} is mashed potatoes!',
  'And {n} is toast! Brutal!',
  'Lights out for {n}! What a way to go!',
];

const ROUND: readonly string[] = [
  'Round {r}! {n} starts. Light it up!',
  'Round {r}! {n} has the spud. Go go go!',
  'Round {r}! Hot hands, {n}! Pass it quick!',
];

const WINNER: readonly string[] = [
  '{n} takes the crown! Absolute legend!',
  '{n} survives the spud! Champion stuff!',
  'Gnarly! {n} wins the whole thing!',
];

export const catchLine = (n: string): string => pick(CATCH).replace('{n}', n);
export const dropLine = (n: string): string => pick(DROP).replace('{n}', n);
export const airborneLine = (): string => pick(AIRBORNE);
export const boomLine = (n: string): string => pick(BOOM).replace('{n}', n);
export const roundLine = (r: number, n: string): string =>
  pick(ROUND).replace('{r}', String(r)).replace('{n}', n);
export const winnerLine = (n: string): string => pick(WINNER).replace('{n}', n);
