import RealityKit
import UIKit

/// One authored phone shell for every scene — live, replay, target and Setup.
/// Parts are named, the pivot is the body center, and materials are kept to
/// the set validated on the physical device so the asset reads identically in
/// every render path.
enum PhoneModelFactory {
    static func makePhone(appearance: PhoneAppearance, accent: UIColor) -> Entity {
        let shape = DeviceShapeDefinition.shape(for: appearance.formFactor)
        let root = Entity()
        root.name = "phone-root"

        let edgeColor = uiColor(appearance.edge.color)
        let bodyColor = uiColor(appearance.body.color)
        let screenColor = appearance.usesLiveScreen ? accent : uiColor(appearance.screen.color)

        // Materials are deliberately conservative: SimpleMaterial was
        // physically validated on-device by the first native build, while a
        // PhysicallyBasedMaterial set rendered black there (no IBL). The
        // screen is unlit so state stays readable under any lighting.
        let frameMaterial = SimpleMaterial(color: edgeColor, roughness: 0.35, isMetallic: true)
        let frame = ModelEntity(
            mesh: .generateBox(
                width: shape.width,
                height: shape.height,
                depth: shape.depth,
                cornerRadius: shape.cornerRadius
            ),
            materials: [frameMaterial]
        )
        frame.name = "phone-frame"
        root.addChild(frame)

        // Back glass: the finish the player customizes.
        let backMaterial = SimpleMaterial(color: bodyColor, roughness: 0.28, isMetallic: true)
        let back = ModelEntity(
            mesh: .generateBox(
                width: shape.width * 0.965,
                height: shape.height * 0.978,
                depth: shape.depth * 0.22,
                cornerRadius: shape.cornerRadius * 0.9
            ),
            materials: [backMaterial]
        )
        back.name = "phone-back"
        back.position.z = -shape.depth * 0.46
        root.addChild(back)

        // Screen: unlit so it glows identically in every render path.
        let screenMaterial = UnlitMaterial(color: screenColor.withAlphaComponent(0.92))
        let screen = ModelEntity(
            mesh: .generateBox(
                width: shape.width * 0.9,
                height: shape.height * 0.92,
                depth: shape.depth * 0.14,
                cornerRadius: shape.cornerRadius * 0.72
            ),
            materials: [screenMaterial]
        )
        screen.name = "phone-screen"
        screen.position.z = shape.depth * 0.48
        root.addChild(screen)

        // Camera island, back top-left, with per-family lens count.
        let island = makeCameraIsland(shape: shape, edgeColor: edgeColor)
        island.position = SIMD3(
            -shape.width * 0.5 + shape.width * 0.19,
            shape.height * 0.5 - shape.width * 0.19,
            -shape.depth * 0.62
        )
        root.addChild(island)

        // Side buttons: power right, volume left.
        let buttonMaterial = frameMaterial
        for (name, x, y, height) in [
            ("phone-button-power", shape.width * 0.5, shape.height * 0.16, shape.height * 0.085),
            ("phone-button-volume-up", -shape.width * 0.5, shape.height * 0.20, shape.height * 0.055),
            ("phone-button-volume-down", -shape.width * 0.5, shape.height * 0.12, shape.height * 0.055),
        ] {
            let button = ModelEntity(
                mesh: .generateBox(
                    width: shape.depth * 0.32,
                    height: Float(height),
                    depth: shape.depth * 0.5,
                    cornerRadius: shape.depth * 0.12
                ),
                materials: [buttonMaterial]
            )
            button.name = name
            button.position = SIMD3(Float(x), Float(y), 0)
            root.addChild(button)
        }

        return root
    }

    private static func makeCameraIsland(shape: DeviceShapeDefinition, edgeColor: UIColor) -> Entity {
        let island = Entity()
        island.name = "phone-camera-island"

        let islandMaterial = SimpleMaterial(color: edgeColor, roughness: 0.4, isMetallic: true)
        let islandSize = shape.width * 0.34
        let plate = ModelEntity(
            mesh: .generateBox(
                width: islandSize,
                height: islandSize,
                depth: shape.depth * 0.30,
                cornerRadius: islandSize * 0.28
            ),
            materials: [islandMaterial]
        )
        plate.name = "phone-camera-plate"
        island.addChild(plate)

        let lensMaterial = SimpleMaterial(color: UIColor(white: 0.05, alpha: 1), roughness: 0.08, isMetallic: false)

        let lensRadius = islandSize * 0.17
        let offsets: [SIMD2<Float>] = shape.cameraLensCount >= 3
            ? [SIMD2(-0.2, 0.2), SIMD2(-0.2, -0.2), SIMD2(0.2, 0)]
            : [SIMD2(-0.18, 0.18), SIMD2(-0.18, -0.18)]
        for (index, offset) in offsets.enumerated() {
            let lens = ModelEntity(
                mesh: .generateCylinder(height: shape.depth * 0.24, radius: lensRadius),
                materials: [lensMaterial]
            )
            lens.name = "phone-camera-lens-\(index)"
            lens.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            lens.position = SIMD3(
                offset.x * islandSize,
                offset.y * islandSize,
                -shape.depth * 0.18
            )
            island.addChild(lens)
        }
        return island
    }

    /// Deterministic scene lighting: virtual-camera RealityViews provide no
    /// environment on device, so every phone scene adds this rig alongside
    /// the phone (never as its child — lights must not spin with the trick).
    /// Key from the viewer's upper front, fill from behind so the back glass
    /// never collapses to black.
    static func makeLightRig() -> Entity {
        let rig = Entity()
        rig.name = "phone-light-rig"

        let key = Entity()
        key.name = "phone-light-key"
        key.components.set(DirectionalLightComponent(color: .white, intensity: 2600))
        key.orientation = simd_quatf(angle: -.pi / 5, axis: SIMD3(1, 0.35, 0))
        rig.addChild(key)

        let fill = Entity()
        fill.name = "phone-light-fill"
        fill.components.set(DirectionalLightComponent(color: .white, intensity: 900))
        fill.orientation = simd_quatf(angle: .pi * 0.82, axis: SIMD3(0.25, 1, 0))
        rig.addChild(fill)

        return rig
    }

    private static func uiColor(_ value: CosmeticOption.ColorValue) -> UIColor {
        UIColor(
            red: CGFloat(value.red),
            green: CGFloat(value.green),
            blue: CGFloat(value.blue),
            alpha: 1
        )
    }
}
