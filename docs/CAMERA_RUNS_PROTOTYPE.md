# Camera Runs prototype contract

This slice is a bounded native prototype for measured replay export and the
Camera Run media spine. It is local-only: no account, cloud sync, social upload
or automatic Photos write is included.

## Camera V2 product direction

`Camera Run` remains the advanced beta bench, but camera capture should not stay
a separate game mode. The next player-facing slice treats camera as an optional
capture layer that can be enabled from Free, Follow, Classic or a future Line
mode:

1. Front and rear sources record against the same monotonic run clock whenever
   multi-camera is supported; constrained devices use an explicit fallback.
2. The live front feed becomes the screen material of the existing 3D phone,
   instead of replacing the phone stage with a flat camera preview.
3. The phone keeps its measured live/replay orientation while the mapped front
   video stays time-aligned. Original camera tracks remain immutable; the
   mapped screen is a composition choice, never destructive preprocessing.
4. A completed result offers a quick ready-to-share composition plus an
   `EDIT VIDEO` route into the existing advanced editor for trims, source
   selection and alternate cuts.
5. The result replay and final export must use the same time mapping. A live
   preview that merely looks synchronized is not sufficient evidence that the
   rendered artifact is synchronized.

Before building the screen material, close the current physical-device export
failure reported as `Operation Stopped` and preserve its underlying error,
export stage and cancellation reason in diagnostics. Do not replace the error
with a generic success/fallback artifact.

## Contracts

- `CameraRunTimeline` is the shared monotonic timebase. It stores ordered
  `preTalk`, `throw` and `postTalk` start/end markers as seconds from a fixed
  `ProcessInfo.systemUptime` origin. Camera host-time sample timestamps can be
  compared to motion timestamps without converting through wall-clock dates.
- `CameraRunCaptureSession` owns an `AVCaptureSession` on the main actor. It
  requests camera permission only when `prepare` is called, reports explicit
  permission/unavailable/interruption/runtime-error states, and exposes the
  latest real camera presentation timestamp. Multi-camera is attempted only
  when `AVCaptureMultiCamSession.isMultiCamSupported` and both lenses exist;
  any unsupported or failed graph falls back to one camera and reports the
  selected mode. Camera samples are routed by physical position so front and
  rear recorders cannot accidentally receive each other's frames.
- `CameraRunVideoRecorder` receives real sample buffers from the capture
  session and writes a video-only MP4 under Application Support. The Camera Run
  screen finalizes those tracks and exposes each saved file through ShareLink.
  Microphone capture is intentionally not requested by this slice.
- `CameraRunDraftClip` keeps source replay frames and/or a camera URL immutable.
  `CameraRunEditorModel` changes only trim, vertical/layout and caption
  metadata. `CameraRunExportPlan` makes composition requirements explicit.
- `ReplayVideoExportPlan` samples the measured `ReplayFrame` timeline at a
  deterministic output cadence. `ReplayVideoExporter` writes a 1080×1920 H.264
  artifact through `AVAssetWriter`; its renderer receives the actual replay
  frame at every timestamp. The included Core Graphics renderer is a bounded
  simulator-safe shell that is replaceable by an offscreen RealityKit renderer.

## Device gates

1. The app target now includes camera, microphone and Photos-add usage strings.
   Camera permission is requested only when the player starts the Camera Run
   prototype; microphone and Photos access are not requested by this slice.
2. If audio is added later, request
   `AVAudioSession` access explicitly, and add an audio track to the timeline
   contract. The current recorder is video-only.
3. The iOS Simulator deliberately returns `.simulatorUnavailable` and never
   asks for camera permission. Replay planning and Core Graphics export remain
   testable there without a camera.
4. Validate front/rear and multi-cam behavior on a physical device. Thermal
   pressure, lens availability and interruption recovery are device/runtime
   gates, not unit-test claims.
5. A future Photos integration must request Photos permission and present a
   user-confirmed share/save action after the local MP4 artifact exists.

## Integration sequence

1. `CameraRunPrototypeView` already creates `CameraRunCaptureSession`, calls `prepare`,
   and show its state before starting capture. Create a `CameraRunTimeline` at
   the same run origin and mark the six UI/motion/camera boundaries as they
   occur.
2. Next, start `CameraRunVideoRecorder` at the chosen output URL, attach it with
   `attachVideoRecorder`, then start the capture session. Stop the session and
   finish the recorder before constructing a draft clip.
3. Build a replay draft from the immutable `ReplayFrame` array (or later a
   `MotionCaptureV3` convenience), pass it through `CameraRunEditorModel`, and
   use `ReplayVideoExportRequest(capture:edit:outputURL:)` for ordinary replay
   export.
4. Present `ReplayVideoArtifact.shareURL` with an explicit `ShareLink` or
   share sheet. There is no social publisher in this prototype.

## Verification

`MediaTimelineTests` covers injected monotonic origins, strict marker order,
and non-destructive editor edits. `MediaExportPlanTests` covers deterministic
trim/frame cadence and explicit camera-composition fallback. Run the app scheme
on an iOS Simulator for compile/UI checks, then run the camera gates on a
physical iPhone; no simulator test can validate camera availability or
multi-camera synchronization.
