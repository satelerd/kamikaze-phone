# Onboarding guide media

Status: planned after the minimal playable onboarding is validated on device.

The 3D target remains the current guide because it is interactive and already
shares the same motion definitions as Practice. It should later be complemented
by a short real-world clip for each trick.

## Clip contract

- Show the hand, release and catch from a spectator-side angle.
- Play once at real speed, then once in slow motion.
- Keep each clip under six seconds and loop without a visible jump.
- Use one representative direction; the onboarding copy must say that either
  direction passes.
- Keep the interactive 3D target available for scrubbing and camera inspection.
- Package clips locally so first-run onboarding does not depend on a network.
- Respect Reduce Motion and provide a still keyframe plus concise text fallback.

The guide is instructional media, not detector ground truth. The detector keeps
judging the captured sensor evidence against the trick family accepted by the
onboarding challenge.
