import Observation
import RealityKit
import UIKit

/// Loads and normalizes the scanned iPhone asset (iPhone 15 Pro Max by
/// MajdyModels, CC BY 4.0, via Sketchfab) once per launch. Observable so
/// phone scenes re-evaluate when the async load lands — the stamp refresher
/// then swaps the procedural stand-in for the real geometry in place.
@MainActor
@Observable
final class PhoneModelLibrary {
    static let shared = PhoneModelLibrary()

    private(set) var realPhone: Entity?
    private var loading = false

    private init() {}

    func preload() {
        guard realPhone == nil, !loading else { return }
        loading = true
        Task { @MainActor in
            defer { loading = false }
            guard let entity = try? await Entity(named: "iPhone15ProMax") else { return }
            realPhone = Self.normalized(entity)
        }
    }

    /// A fresh instance for one scene. Entities cannot live in two scenes,
    /// so every request clones the normalized master.
    func makeRealPhone() -> Entity? {
        realPhone?.clone(recursive: true)
    }

    /// Portrait meters with a centered pivot, matching the procedural
    /// factory's contract so cameras and replays frame it identically.
    private static func normalized(_ raw: Entity) -> Entity {
        convertMaterials(raw)

        let wrapper = Entity()
        wrapper.name = "phone-root"
        let holder = Entity()
        holder.name = "phone-real-holder"
        wrapper.addChild(holder)
        holder.addChild(raw)

        // Stand the phone upright: GLTF-converted scans often arrive lying
        // flat (largest extent on Z). Detect and rotate instead of trusting
        // the export's axes.
        var bounds = raw.visualBounds(relativeTo: wrapper)
        var extents = bounds.extents
        if extents.z > extents.y, extents.z >= extents.x {
            holder.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        } else if extents.x > extents.y, extents.x >= extents.z {
            holder.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        }

        bounds = holder.visualBounds(relativeTo: wrapper)
        extents = bounds.extents
        let targetHeight = DeviceShapeDefinition.shape(for: .real).height
        let maxExtent = max(extents.x, max(extents.y, extents.z))
        if maxExtent > 0 {
            holder.scale *= SIMD3(repeating: targetHeight / maxExtent)
        }

        bounds = holder.visualBounds(relativeTo: wrapper)
        holder.position -= bounds.center

        return wrapper
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
                return simple
            }
            entity.components.set(model)
        }
        for child in entity.children {
            convertMaterials(child)
        }
    }
}
