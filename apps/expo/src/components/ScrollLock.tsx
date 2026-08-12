import { createContext, useContext } from 'react';

export const ScrollLockContext = createContext<(locked: boolean) => void>(() => undefined);

export function useScrollLock() {
  return useContext(ScrollLockContext);
}
