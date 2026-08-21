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
2. Build procedural iPhone 15, 16 and 17 families with base, Plus, Pro and Pro
   Max variants where those products exist. Use official published dimensions;
   do not invent unreleased iPhone 18 hardware.
3. Add a brand-neutral procedural Android device.
4. Add Pixel or Galaxy hero meshes only when an individual CC0 or CC BY asset
   has an unambiguous redistribution license.
5. Validate each mesh with `usdchecker`, normalize its origin and pivot, cap
   texture/triangle cost, test it in RealityKit, and generate a selector
   thumbnail.

Gameplay remains device-independent: detector coordinates and scoring must not
change when the player equips a different cosmetic model.
