# Early game explorations

These directories preserve complete, runnable snapshots from the first independent game-design pull requests. They are historical references, not dependencies of either active application.

- `pr-01-game-modes`: first Kamikaze Classic and Trick Throw game modes.
- `pr-02-ui-debug`: alternate UI/debug refinement with explicit sensor-permission handling.

Each `source/` directory is the exact tracked tree from its original pull-request head. Use the README beside it for provenance and run instructions.

These snapshots intentionally retain their original 2024 dependency locks. They compile, but `npm audit` reports known vulnerabilities in that historical stack; do not deploy them as production applications.
