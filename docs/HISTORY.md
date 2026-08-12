# Project history

The repository uses folders for distinct implementations and Git tags for immutable milestones of the same implementation. This preserves the real history without maintaining several diverging copies of identical source files.

## Milestones

| Era | Git reference | Location at that point | Description |
| --- | --- | --- | --- |
| Original web exploration | `web-prototype-v0.1.0` | repository root | First Next.js sensor/game experiments. Its latest runnable form is also preserved at `archive/web-prototype/` on the current branch. |
| First game-mode branch | `exploration-game-modes-v0.1.0` | `archive/explorations/pr-01-game-modes/source/` | PR #1 snapshot with Kamikaze Classic and Trick Throw. |
| UI/debug branch | `exploration-ui-debug-v0.1.0` | `archive/explorations/pr-02-ui-debug/source/` | PR #2 snapshot with alternate UI, debugging and sensor-permission handling. |
| Motion laboratory | `testing-v0.2.0` | `mobile/` | Expo sensors, detector math, calibration, trick catalog and interactive replay workshop. |
| Playable Expo alpha | `expo-game-v0.3.0` | `mobile/` | Onboarding, Play, Practice, Locker, Profile and the complete game-experience alpha. |
| Native iOS beta | `codex/native-beta` | `apps/ios/` on the current branch | SwiftUI, RealityKit and Core Motion rewrite in progress. |
| Native device detector checkpoint | `native-beta-device-detector-v0.1.0` | `apps/ios/` | First signed iPhone build with validated live pose, native visual system and experimental automatic capture closure. Not a classifier-accuracy milestone. |

The old path shown for a tag is intentional: checking out a historical snapshot recreates the repository exactly as it existed then.

## Inspect an old version without disturbing current work

Git worktrees are the safest way to run two eras simultaneously:

```sh
git worktree add ../kamikaze-motion-lab testing-v0.2.0
git worktree add ../kamikaze-expo-alpha expo-game-v0.3.0
```

Remove a worktree after use with `git worktree remove <path>`. Do not commit directly on a detached tag; create a branch if the experiment will continue.

## Other exploratory branches

These branches are retained for provenance but are not current product baselines:

- `codex/mobile-motion-prototype`: development line leading to the motion-lab tag.
- `codex/game-experience-prototype`: development line leading to the Expo game alpha and native plan.
- `codex/crear-juego-inspirado-en-kamikaze-phone`: early game-mode exploration, also materialized under `archive/explorations/pr-01-game-modes`.
- `69m7sm-codex/crear-juego-inspirado-en-kamikaze-phone`: early UI/debug variation, also materialized under `archive/explorations/pr-02-ui-debug`.
- `cursor/desarrollar-mec-nicas-y-ui-del-juego-c31b`: separate early sensor-game implementation.

Before reviving one, compare its behavior with the reviewed fixtures and current detector contracts. These branches may contain useful ideas, but they are not assumed to be compatible with either active app.
