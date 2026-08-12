import { useEffect, useMemo, useState } from 'react';

import {
  buildDefaultTrickCatalog,
  type GripHand,
  type TrickDefinition,
} from '../motion/trickCatalog';
import {
  loadCustomTricks,
  loadGripHand,
  saveCustomTricks,
  saveGripHand,
} from '../storage/trickCatalog';

export function useTrickCatalog() {
  const [gripHand, setGripHandState] = useState<GripHand>('right');
  const [customTricks, setCustomTricks] = useState<TrickDefinition[]>([]);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    Promise.all([loadGripHand(), loadCustomTricks()]).then(([storedHand, storedTricks]) => {
      setGripHandState(storedHand);
      setCustomTricks(storedTricks);
      setReady(true);
    });
  }, []);

  const definitions = useMemo(
    () => [...buildDefaultTrickCatalog(gripHand), ...customTricks],
    [customTricks, gripHand],
  );

  const setGripHand = (hand: GripHand) => {
    setGripHandState(hand);
    saveGripHand(hand).catch(() => undefined);
  };

  const saveDefinition = (definition: TrickDefinition) => {
    setCustomTricks((existing) => {
      const next = [definition, ...existing.filter(({ id }) => id !== definition.id)];
      saveCustomTricks(next).catch(() => undefined);
      return next;
    });
  };

  return { customTricks, definitions, gripHand, ready, saveDefinition, setGripHand };
}

export type TrickCatalogController = ReturnType<typeof useTrickCatalog>;
