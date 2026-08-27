import Observation
import RealityKit
import UIKit

/// The downloadable phone assets, keyed by their bundled resource name.
nonisolated enum PhoneAssetID: String, CaseIterable, Sendable {
    /// iPhone 15 Pro Max by MajdyModels — CC BY 4.0, via Sketchfab. Baked
    /// titanium textures; renders as-is.
    case scanned = "iPhone15ProMax"
    /// iPhone 15 Pro Max (low-poly) by LagzDesign — CC BY, via Sketchfab.
    /// Flat-color materials by named part, so cosmetics can tint it.
    case paintable = "iPhone15Lowpoly"
    /// iPhone 17 Pro Max by MajdyModels — CC BY 4.0, via Sketchfab.
    case iPhone17ProMax = "iPhone17ProMaxHero"
    /// Google Pixel 8 Pro low-poly by LagzDesign — CC BY 4.0, via Sketchfab.
    case pixel8Pro = "Pixel8Pro"

    var targetFormFactor: PhoneFormFactor {
        switch self {
        case .scanned: .real
        case .paintable: .paint
        case .iPhone17ProMax: .iPhone17ProMaxReal
        case .pixel8Pro: .pixel8Pro
        }
    }
}

/// Loads and normalizes the downloaded iPhone assets once per launch.
/// Observable so phone scenes re-evaluate when an async load lands — the
/// stamp refresher then swaps the procedural stand-in in place.
@MainActor
@Observable
final class PhoneModelLibrary {
    static let shared = PhoneModelLibrary()

    private(set) var loaded: [PhoneAssetID: Entity] = [:]
    /// Assets that completed a load attempt but could not be decoded. The
    /// launch gate treats these as resolved so a broken optional model can
    /// fall back to procedural geometry instead of trapping the app on a
    /// loading screen.
    private(set) var failed: Set<PhoneAssetID> = []
    private var loading: Set<PhoneAssetID> = []

    private init() {}

    func preload() {
        for asset in PhoneAssetID.allCases {
            guard loaded[asset] == nil,
                  !loading.contains(asset),
                  !failed.contains(asset)
            else { continue }
            loading.insert(asset)
            Task { @MainActor in
                defer { loading.remove(asset) }
                guard let entity = try? await Entity(named: asset.rawValue) else {
                    failed.insert(asset)
                    return
                }
                loaded[asset] = Self.normalized(entity, asset: asset)
            }
        }
    }

    func isLoaded(_ asset: PhoneAssetID) -> Bool {
        loaded[asset] != nil
    }

    /// A fresh instance for one scene. Entities cannot live in two scenes,
    /// so every request clones the normalized master.
    func makePhone(_ asset: PhoneAssetID) -> Entity? {
        loaded[asset]?.clone(recursive: true)
    }

    /// Portrait meters with a centered pivot, matching the procedural
    /// factory's contract so cameras and replays frame it identically.
    private static func normalized(_ raw: Entity, asset: PhoneAssetID) -> Entity {
        convertMaterials(raw)
        if asset == .iPhone17ProMax {
            removeOpaqueDisplayCover(from: raw)
        }

        let wrapper = Entity()
        wrapper.name = "phone-root"
        let holder = Entity()
        holder.name = "phone-real-holder"
        wrapper.addChild(holder)
        holder.addChild(raw)

        // Stand the phone upright: GLTF-converted assets often arrive lying
        // flat (largest extent on Z). Detect and rotate instead of trusting
        // the export's axes.
        var bounds = raw.visualBounds(relativeTo: wrapper)
        var extents = bounds.extents
        if extents.z > extents.y, extents.z >= extents.x {
            holder.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        } else if extents.x > extents.y, extents.x >= extents.z {
            holder.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        }

        // Portrait but facing sideways (faces toward ±X): yaw so the flat
        // faces meet the camera — a phone is wider than it is deep.
        bounds = holder.visualBounds(relativeTo: wrapper)
        extents = bounds.extents
        if extents.z > extents.x {
            holder.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 1, 0)) * holder.orientation
        }

        bounds = holder.visualBounds(relativeTo: wrapper)
        extents = bounds.extents
        let targetHeight = DeviceShapeDefinition.shape(for: asset.targetFormFactor).height
        let maxExtent = max(extents.x, max(extents.y, extents.z))
        if maxExtent > 0 {
            holder.scale *= SIMD3(repeating: targetHeight / maxExtent)
        }

        bounds = holder.visualBounds(relativeTo: wrapper)
        holder.position -= bounds.center

        return wrapper
    }

    /// The iPhone 17 asset authors a transparent glass sheet in front of its
    /// display. RealityKit's no-IBL material conversion makes that sheet
    /// opaque, hiding the actual screen. Remove only its renderer; the screen,
    /// bezel and all physical geometry remain intact.
    private static func removeOpaqueDisplayCover(from entity: Entity) {
        if entity.name.lowercased().contains("glass_002") {
            entity.components.remove(ModelComponent.self)
        }
        for child in entity.children {
            removeOpaqueDisplayCover(from: child)
        }
    }

    /// PhysicallyBasedMaterial renders black in the app's virtual-camera
    /// scenes on device (no IBL) — the same gotcha the procedural factory
    /// hit. Rebuild every imported material as SimpleMaterial, preserving
    /// the base color texture and tint, so the validated light rig works.
    private static func convertMaterials(_ entity: Entity) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard let pbr = material as? PhysicallyBasedMaterial else { return material }
                var simple = SimpleMaterial()
                if let texture = pbr.baseColor.texture {
                    simple.color = .init(tint: pbr.baseColor.tint, texture: texture)
                } else {
                    simple.color = .init(tint: pbr.baseColor.tint)
                }
                simple.roughness = .init(floatLiteral: 0.42)
                simple.metallic = 0.0
                simple.faceCulling = .none
                return simple
            }
            entity.components.set(model)
        }
        for child in entity.children {
            convertMaterials(child)
        }
    }
}

/// Pure launch policy kept separate from RealityKit loading so the critical
/// no-flash behavior is deterministic and unit-testable.
nonisolated enum PhoneAppearanceLaunchGate {
    static func canRender(
        appearance: PhoneAppearance,
        loadedAssets: Set<PhoneAssetID>,
        failedAssets: Set<PhoneAssetID>
    ) -> Bool {
        guard let requestedAsset = PhoneModelFactory.assetID(for: appearance.formFactor) else {
            return true
        }
        return loadedAssets.contains(requestedAsset) || failedAssets.contains(requestedAsset)
    }
}

extension PhoneModelLibrary {
    /// Mean luminance of the paintable asset's baked back texture. Tints are
    /// boosted by its inverse so the rendered back lands near the chosen
    /// cosmetic color instead of a multiply-darkened version of it.
    private static let paintableBackLuminance = 0.36

    /// Applies the player's body/edge cosmetics to the paintable asset. Parts
    /// are matched by the mesh names authored in the source model; anything
    /// unmatched (lenses, screws, screen) keeps its authored look.
    static func applyCosmetics(
        to phone: Entity,
        appearance: PhoneAppearance,
        screenLabel: String? = nil
    ) {
        let body = appearance.bodyColor
        // Uniform boost, clamped so hue survives: per-component clamping
        // would bleach saturated colors toward white.
        let boost = min(
            1.0 / paintableBackLuminance,
            1.0 / max(body.red, max(body.green, body.blue), 0.001)
        )
        let backTint = UIColor(
            red: min(1, body.red * boost),
            green: min(1, body.green * boost),
            blue: min(1, body.blue * boost),
            alpha: 1
        )
        let edge = appearance.edgeColor
        let edgeTint = UIColor(red: edge.red, green: edge.green, blue: edge.blue, alpha: 1)
        tintParts(of: phone, matching: "back_color", tint: backTint, keepTexture: true)
        tintParts(of: phone, matching: "Cube_sides", tint: edgeTint, keepTexture: false)
        // "Cube_screen_0" never matches the separate "Cube_screen_border_0".
        // Flipped: this mesh's UVs expect the GLTF pre-flipped orientation.
        if let screenLabel,
           let labelled = PhoneModelFactory.labelledScreenMaterial(
               text: screenLabel,
               flippedVertically: true
           ) {
            replaceMaterials(of: phone, matching: "Cube_screen_0", with: labelled)
        } else if appearance.usesCustomPhotoScreen,
           let photo = PhoneModelFactory.customPhotoScreenMaterial(flippedVertically: true) {
            replaceMaterials(of: phone, matching: "Cube_screen_0", with: photo)
        }
    }

    /// The Pixel USDZ ships its back under `Plane_color_0`. Its imported PBR
    /// stack becomes partially transparent in our no-IBL RealityKit scenes,
    /// so replace that one body surface with an opaque authored finish. The
    /// camera bar and lenses keep their source materials.
    static func applyPixelCosmetics(
        to phone: Entity,
        appearance: PhoneAppearance
    ) {
        let body = appearance.bodyColor
        let bodyTint = UIColor(
            red: body.red,
            green: body.green,
            blue: body.blue,
            alpha: 1
        )
        let edge = appearance.edgeColor
        let edgeTint = UIColor(
            red: edge.red,
            green: edge.green,
            blue: edge.blue,
            alpha: 1
        )
        var bodyMaterial = SimpleMaterial(
            color: bodyTint,
            roughness: 0.30,
            isMetallic: false
        )
        bodyMaterial.faceCulling = .none
        replaceMaterials(
            of: phone,
            matching: "Plane_color_0",
            with: bodyMaterial
        )
        var edgeMaterial = SimpleMaterial(
            color: edgeTint,
            roughness: 0.24,
            isMetallic: true
        )
        edgeMaterial.faceCulling = .none
        replaceMaterials(
            of: phone,
            matching: "Plane_corners_0",
            with: edgeMaterial
        )
    }

    private static func replaceMaterials(
        of entity: Entity,
        matching nameFragment: String,
        with material: any RealityKit.Material
    ) {
        if entity.name.contains(nameFragment), var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { _ in material }
            entity.components.set(model)
        }
        for child in entity.children {
            replaceMaterials(of: child, matching: nameFragment, with: material)
        }
    }

    private static func tintParts(
        of entity: Entity,
        matching nameFragment: String,
        tint: UIColor,
        keepTexture: Bool
    ) {
        if entity.name.contains(nameFragment), var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard var simple = material as? SimpleMaterial else { return material }
                if keepTexture, let texture = simple.color.texture {
                    simple.color = .init(tint: tint, texture: texture)
                } else {
                    simple.color = .init(tint: tint)
                }
                return simple
            }
            entity.components.set(model)
        }
        for child in entity.children {
            tintParts(of: child, matching: nameFragment, tint: tint, keepTexture: keepTexture)
        }
    }
}
