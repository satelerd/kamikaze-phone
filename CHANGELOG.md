# Changelog

Kamikaze uses semantic product versions for the native iOS beta. Release
candidates share the final app version and receive an `-rc.N` Git tag until the
physical-device checklist passes.

## 0.2.0-rc.1 — pending physical validation

App version `0.2.0` · Apple build `2`

### Highlights

- Camera can be enabled from Play instead of living only as a separate game
  mode, with the live selfie feed rendered on the moving 3D phone.
- Camera runs preserve front/rear source tracks and microphone audio for a
  non-destructive editor.
- Measured replay exports support a native SwiftUI/RealityKit visual, vertical
  composition, branded glass cards and optional slow motion during the trick.
- The community feed now pages one dominant post at a time and autoplays only
  its 3D replay.
- Setup adds licensed real-device meshes, custom screen media and a documented
  asset catalog alongside the Sloppy Phone easter egg.

### Candidate gates

- [x] Native motion-core tests pass.
- [x] iOS Simulator build passes.
- [x] Focused phone appearance, screen mapping, orientation and speed-ramp tests
  pass.
- [ ] Install build `2` on the reference iPhone.
- [ ] Record, seal and replay one camera-enabled throw with microphone audio.
- [ ] Export at 1x and slow motion, then save both videos to Photos.
- [ ] Confirm the title card, lower score card, screen orientation and phone
  scale in the exported files.
- [ ] Check Pixel/iPhone real meshes from front and rear in Setup.
- [ ] Confirm Feed snaps smoothly between consecutive posts.

### Known beta limits

- The detector and score remain provisional and require broader reviewed motion
  evidence.
- Community trick creation and cloud/social workflows are foundations, not a
  complete moderation or discovery system.
- Camera export is intentionally foreground work for this candidate; the app
  keeps the screen awake and reports progress rather than promising background
  completion.
