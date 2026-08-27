# Device assets and catalog

This document is the source of truth for third-party device meshes and the
planned multi-device catalog. A model is not eligible for a public build until
its source, license and modifications are recorded here.

## Bundled third-party assets

### iPhone 15 Pro Max — MajdyModels

- Local resource: `Kamikaze/Resources/Models/iPhone15ProMax.usdz`
- Creator: MajdyModels (`@MG990`)
- Source: <https://sketchfab.com/3d-models/iphone-15-pro-max-5b7b35513a154ac69619dc2b2fe15686>
- License recorded when downloaded: Creative Commons Attribution 4.0
- Use: baked-material `REAL 15 PRO` option
- Runtime modification: scale, axes and pivot are normalized for RealityKit

### iPhone 15 Pro Max low-poly — LagzDesign

- Local resource: `Kamikaze/Resources/Models/iPhone15Lowpoly.usdz`
- Creator: LagzDesign (`@LagzDesign`)
- Source: <https://sketchfab.com/3d-models/iphone-15-pro-max-cda5d8cdffee41fd8c5cb199bd40cd9a>
- License recorded when downloaded: Creative Commons Attribution (version not
  preserved in the original project notes; verify it on the listing before a
  public release)
- Use: recolorable `PAINT 15` option
- Runtime modification: materials, scale, axes and pivot are normalized for
  RealityKit

### iPhone 17 Pro Max — MajdyModels (experimental)

- Local resource: `Kamikaze/Resources/Models/iPhone17ProMaxHero.usdz`
- Creator: MajdyModels (`@MG990`)
- Source: <https://sketchfab.com/3d-models/iphone-17-pro-max-87fc1df741384124a8ce0226d2b2058d>
- License confirmed in the 2026-08-25 download dialog: Creative Commons
  Attribution 4.0
- Use: opt-in `17 PRO MAX · REAL` hero/live evaluation; it does not replace
  the lightweight procedural model
- Runtime modification: scale, axes, pivot and materials are normalized for
  RealityKit; `Cube_010_screen_001_0` is the dedicated display mesh

### Google Pixel 8 Pro low-poly — LagzDesign (experimental)

- Local resource: `Kamikaze/Resources/Models/Pixel8Pro.usdz`
- Creator: LagzDesign (`@LagzDesign`)
- Source: <https://sketchfab.com/3d-models/google-pixel-8-pro-low-poly-9214c34d4a1b46538f0696492e4ac246>
- License confirmed in the 2026-08-25 download dialog: Creative Commons
  Attribution 4.0
- Use: opt-in `PIXEL 8 PRO · REAL` Android/live evaluation
- Runtime modification: scale, axes, pivot and materials are normalized for
  RealityKit; `Plane_main_screen_0` is the dedicated display mesh

Both listings and their license versions must be rechecked before App Store
distribution. Product names and shapes identify compatibility; Kamikaze is not
affiliated with or endorsed by Apple, Google or Samsung.

## Catalog direction

The scalable catalog should use a versioned `DeviceDescriptor` instead of one
enum case per downloaded mesh. Each descriptor owns:

- stable ID, brand, family, generation and size variant;
- authored dimensions, corner radius and camera layout;
- supported finishes;
- procedural or USDZ rendering source;
- optional third-party license record.

Implementation order:

1. Preserve the current iPhone 15 Pro Max meshes and expose their credits in
   the app.
2. Keep generated hardware out of the player-facing catalog. One intentionally
   rough iPhone 15 Pro-shaped model remains as the `SLOPPY PHONE` easter egg;
   legacy generated IDs remain decodable only so old local saves do not break.
3. Add Pixel or Galaxy hero meshes only when an individual CC0 or CC BY asset
   has an unambiguous redistribution license.
4. Validate each mesh with `usdchecker`, normalize its origin and pivot, cap
   texture/triangle cost, test it in RealityKit, and generate a selector
   thumbnail.

Gameplay remains device-independent: detector coordinates and scoring must not
change when the player equips a different cosmetic model.

## Candidate repertoire — 2026-08-25

This began as a research shortlist. Pixel 8 Pro and iPhone 17 Pro Max have now
advanced to opt-in experimental bundled assets; the remaining candidates must
still pass the download-dialog license check, visual inspection, screen
replacement test and device performance gate before they are added to the app.

### Recommended next downloads

| Priority | Device | Creator | Geometry | Intended tier | Status |
| --- | --- | --- | ---: | --- | --- |
| P0 | iPhone 16 Pro Max low-poly | Babkakvaser228 | 11.7k triangles | live gameplay | CC Attribution listing; inspect screen mesh and materials |
| P0 | Google Pixel 8 Pro low-poly | LagzDesign | 9.4k triangles | live gameplay | CC Attribution; listing explicitly supports replaceable screen image/video |
| P1 | iPhone 17 Pro Max | MajdyModels | 29.6k triangles | hero/replay first | same creator as the current real iPhone; profile on device before live use |
| P1 | Samsung S22 Ultra | MajdyModels | 17.9k triangles | hero/replay, possible live | CC Attribution; screen topology still unknown |
| P1 | Samsung Galaxy S24 Plus | Davetheconqueror | 9.4k triangles | Android live candidate | CC Attribution; listing warns dimensions may differ from the real device |
| P2 | Samsung Galaxy S24 Ultra | thatdragon516 | 16.1k triangles | Android hero/replay | CC Attribution; inspect materials and screen topology |
| P2 | Generic low-poly Android | Louken | 816 triangles | accessibility/performance fallback | CC Attribution; visually inspect before replacing our procedural generic model |

Candidate sources:

- iPhone 16 Pro Max low-poly: <https://sketchfab.com/3d-models/iphone-16-pro-max-low-poly-3d-3a2da262ec834377aef176b0b13c4a62>
- Google Pixel 8 Pro low-poly: <https://sketchfab.com/3d-models/google-pixel-8-pro-low-poly-9214c34d4a1b46538f0696492e4ac246>
- iPhone 17 Pro Max: <https://sketchfab.com/3d-models/iphone-17-pro-max-87fc1df741384124a8ce0226d2b2058d>
- Samsung S22 Ultra: <https://sketchfab.com/3d-models/samsung-s22-ultra-ea625421bab14c34a0c7c759a02e6fa3>
- Samsung Galaxy S24 Plus: <https://sketchfab.com/3d-models/samsung-galaxy-s24-plus-deda550f064141c3bf3b9e7190a2ac39>
- Samsung Galaxy S24 Ultra: <https://sketchfab.com/3d-models/samsung-galaxy-s24-15db21d28d60492bbc157fb0c90cfe9f>
- generic low-poly Android: <https://sketchfab.com/3d-models/low-poly-android-phone-2034cfdf35d14186b06d4ca63b25dda0>

The 51.5k-triangle iPhone 16 Pro Max from MajdyModels is intentionally not in
the first download batch. It is a useful visual reference, but the lighter
11.7k version is a better live-render candidate. Likewise, fan-made unreleased
phones, models with non-commercial/no-derivatives terms, contradictory license
copy, or promotional placeholder geometry are not eligible.

### Acceptance gates

1. Copy the exact attribution text and license shown in the Sketchfab download
   dialog into this document before committing the asset.
2. Download USDZ when supplied; otherwise prefer glTF/FBX plus textures and
   preserve the unmodified source archive outside the app bundle.
3. Run `usdchecker`, then normalize scale, forward axis and centered pivot.
4. Identify a dedicated front-screen mesh. It must accept a live camera/video
   texture without changing the back glass or camera island.
5. Keep one material slot for screen content and minimize expensive transparent
   materials. The live tier must remain fluid while Core Motion samples at
   100 Hz; hero-only models must never silently replace the live tier.
6. Validate front/back orientation, mirrored selfie preview policy, replay,
   direct video export and Story Cut export on a physical iPhone.
7. Add creator, source URL, license and modifications to in-app credits before
   shipping the model in any public build.

### Intake status

The following files were downloaded to the local intake workstation on
2026-08-25. Pixel 8 Pro and iPhone 17 Pro Max were promoted to experimental
bundled resources; iPhone 16 Pro Max and Samsung S22 Ultra remain quarantined.

| Candidate | Local download | SHA-256 | Intake result |
| --- | --- | --- | --- |
| Pixel 8 Pro | `Google_Pixel_8_Pro_low-poly.usdz` | `aa4a0464012d8cf5a765646c2e371756aeae7970269eea2f0910fcecff5e45c6` | bundled experimental spike; dedicated `Plane_main_screen_0` mesh and small 355 KB archive |
| iPhone 17 Pro Max | `iPhone_17_Pro_Max.usdz` | `959903f1d012b9c900add40f3166650e26350c4cd7aca76d8f85a3f057c02e50` | bundled experimental hero/live spike; dedicated `Cube_010_screen_001_0` mesh, 3.5 MB archive |
| iPhone 16 Pro Max low-poly | `Iphone_16_Pro-Max_Low_poly_3D.usdz` | `fefa03a495c62e8db3b3e897b6a69a380b288723026c5c5a6dd91afb379a3fe2` | hold; light 189 KB archive but converted mesh/material names do not identify the display safely |
| Samsung S22 Ultra | `Samsung_S22_Ultra.usdz` | `a54e40637c2cf5d3a063fb9d203f4df4a88b4f23c8e0228aba0fce04bda5c3b2` | hold; useful Android silhouette but converted hierarchy does not identify the display safely |

The Sketchfab download dialogs confirmed CC BY 4.0 for all four files and
explicitly stated that commercial use is allowed with creator attribution.
`usdchecker` reports the same Sketchfab-conversion issues already seen in the
existing assets: missing `MaterialBindingAPI` annotations and, for textured
models, token-vs-string UV input warnings. Passing RealityKit loading and
on-device rendering remains mandatory; the checker result alone is not a
reason to ship or reject an asset.
