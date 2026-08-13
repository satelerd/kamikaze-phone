# VIDEO-TO-3D: Trick Lab reconstruction + the DA3 bundle

Trick Lab records a slow-motion clip of every throw while the IMU reconstructs the
flight. This document covers:

1. what the in-app 3D visualization actually is (and how it approximates the
   nano-world-model `video_to_3d` pipeline),
2. the **DA3 bundle** export format,
3. how to run the *real* point-cloud pipeline on the raw clip.

Reference: [nano-world-model `video_to_3d`](https://github.com/simchowitzlabpublic/nano-world-model/blob/main/docs/applications/video_to_3d.md),
where video frames become camera frusta posed along a 3D trajectory and DA3
(Depth Anything 3) lifts them into a dense point cloud.

---

## 1. What Trick Lab captures

Two synchronized streams per throw:

| Stream | Source | Rate | Contents |
|---|---|---|---|
| Video | `getUserMedia` + `MediaRecorder` | 120 fps requested, camera decides (Pixel 9 / iPhone honor what they can) | The clip, trimmed in playback around the flight window |
| IMU | `SensorEngine` → `ThrowTracker` | device rate (~100 Hz) | Freefall detection, gyro-integrated orientation quaternions, ballistic position reconstruction |

Sync: the recorder start is timestamped with `performance.now()`; every IMU sample
continuously refreshes an engine-time → wall-clock offset, so launch and land map to
exact video times. A ~0.4 s pre-roll absorbs encoder startup jitter.

Coordinate frame (matches `TrajectoryPoint` in `src/lib/types.ts`):

- origin at the launch point, **+y is up**, units are meters
- vertical motion is ballistic (`h = g·T²/8` from the measured airtime)
- horizontal velocity comes from integrating windup acceleration
- orientation is the gyro-integrated device quaternion per sample

## 2. The in-app visualization (DA3-viewer style)

`src/components/TrajectoryViewer.tsx` renders, with plain imperative three.js:

- a dark scene with a ground grid,
- the flight path as a glowing tube,
- a phone marker animated along the path, oriented by the recorded quaternions,
- **8 to 16 video frames drawn to canvas textures and posed as small camera-frustum
  cards along the trajectory at their timestamps**, exactly the way the DA3 viewer
  lays out per-frame camera frusta along the estimated camera path,
- a playhead: scrubbing the slow-mo replay moves the 3D marker and highlights the
  frustum card nearest in time (in demo mode the viewer self-animates).

### How this approximates the real pipeline

| | Trick Lab (in-app, real time) | nano-world-model (offline) |
|---|---|---|
| Camera poses | measured by the IMU (gyro + ballistics) | estimated by DA3 from the images |
| Geometry | trajectory curve only | dense multi-view point cloud |
| Frames | posed image cards (frusta) | back-projected 3D points per pixel |
| Runtime | instant, on the phone | GPU minutes, offline |

The important inversion: the offline pipeline *derives* poses from pixels; Trick Lab
already *knows* the poses from the sensors and uses the pixels as texture. That is
why the export below is interesting: it pairs images with independently measured
poses, which can seed, check, or scale-calibrate a DA3 reconstruction (monocular
pipelines have no absolute scale; the IMU trajectory is metric).

## 3. DA3 bundle format

`Export DA3 bundle` downloads a single JSON file
(`kamikaze-da3-<trick>-<timestamp>.json`), built in
`src/modes/trick-lab/exportBundle.ts`:

```jsonc
{
  "format": "kamikaze-da3-bundle",
  "version": 1,
  "trick": { "id": "pancake-double", "grade": "A", "score": 71, "airtimeSec": 0.8, "heightM": 0.78, "rotationDeg": { "x": 705, "y": 12, "z": 8 } },
  "capture": { "widthPx": 1280, "heightPx": 720, "fps": 60, "facing": "environment", "exposureLocked": true, "mimeType": "video/webm;codecs=vp9" },
  "intrinsicsGuess": {
    "model": "pinhole",
    "widthPx": 1280, "heightPx": 720,
    "fx": 949.3, "fy": 949.3, "cx": 640, "cy": 360,
    "note": "Guessed from a 68 degree horizontal FOV assumption, not calibrated..."
  },
  "coordinateFrame": { "origin": "launch point", "up": "+y", "units": "meters", "quaternions": "device orientation from gyro integration, order [x, y, z, w]" },
  "poses": [ { "tMs": 0, "position": [0, 0, 0], "quaternionXYZW": [0, 0, 0, 1] }, ... ],
  "frames": [ { "index": 0, "tMs": 0, "videoTimeSec": 1.204, "placeholder": false, "jpegBase64": "..." }, ... ]
}
```

Notes:

- `poses` is the full IMU trajectory (~100 Hz), one entry per sample.
- `frames` holds up to **12 JPEG frames** (base64, 480 px wide) sampled evenly across
  the flight window. `placeholder: true` marks desktop-demo gradient frames.
- `intrinsicsGuess` is exactly that: a pinhole guess from a 68 degree horizontal FOV.
  Real reconstructions should let DA3 estimate intrinsics from the imagery.
- The poses are the **phone's** pose. The camera looks out along device −z; apply
  your preferred device-to-camera extrinsic if you need optical-center poses.

Decode the frames with any base64 tool, e.g.:

```bash
jq -r '.frames[].jpegBase64' bundle.json | while read -r b64; do
  i=$((i + 1)); echo "$b64" | base64 -d > "frame_$i.jpg"
done
```

## 4. Running the real pipeline (full point cloud)

The in-app viewer stops at frusta. For a dense reconstruction, run the raw clip
through nano-world-model's `video_to_3d` application. Use the
**Save raw clip** button on the review screen to download the recording
(`.webm` on Android Chrome, `.mp4` on iOS Safari; convert with
`ffmpeg -i clip.webm clip.mp4` if the pipeline wants mp4).

Following the upstream doc:

```bash
git clone https://github.com/simchowitzlabpublic/nano-world-model
cd nano-world-model
# install per the repo README (Python env + DA3 weights)

python video_to_pointcloud.py \
  --video kamikaze-clip.mp4 \
  --max_frames 30 \
  --conf_threshold 40
```

What happens, per the upstream docs:

- the video is subsampled to at most `--max_frames 30` frames,
- **DA3 multi-view** estimates per-frame depth, camera intrinsics and poses jointly
  across the frame set,
- per-pixel depth below the `--conf_threshold 40` confidence cut is dropped,
- surviving pixels are back-projected and fused into a **PLY point cloud**,
- the result opens in the **viser** web viewer (camera frusta drawn along the
  estimated trajectory, point cloud around them), which is the look our in-app
  viewer imitates.

Tips specific to Kamikaze Phone clips:

- Throws are short; 30 frames across a ~1 s flight is plenty. Trim the clip to the
  flight window first (`ffmpeg -ss <launch> -to <land> -i clip.mp4 out.mp4`) so the
  frame budget is spent airborne, not on your feet.
- A phone spinning through the air is a hard case for pose estimation (motion blur,
  rolling shutter, fast rotation). Bright light + the locked short exposure help
  DA3 as much as they help the slow-mo replay.
- Cross-check the DA3 camera path against `poses` in the bundle: it is an
  independent, metric measurement of the same flight. Scale the point cloud so the
  two paths match and the reconstruction inherits real-world meters.
