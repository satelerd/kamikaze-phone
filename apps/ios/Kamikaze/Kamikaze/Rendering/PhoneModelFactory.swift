import RealityKit
import UIKit

/// One authored phone shell for every scene — live, replay, target and Setup.
/// Parts are named, the pivot is the body center, and materials are
/// physically based so the same asset reads correctly in every field state.
enum PhoneModelFactory {
    static func makePhone(appearance: PhoneAppearance, accent: UIColor) -> Entity {
        let shape = DeviceShapeDefinition.shape(for: appearance.formFactor)
        let root = Entity()
        root.name = "phone-root"

        let edgeColor = uiColor(appearance.edge.color)
        let bodyColor = uiColor(appearance.body.color)
        let screenColor = appearance.usesLiveScreen ? accent : uiColor(appearance.screen.color)

        // Frame: the metal rail that wraps the phone.
        var frameMaterial = PhysicallyBasedMaterial()
        frameMaterial.baseColor = .init(tint: edgeColor)
        frameMaterial.metallic = 1.0
        frameMaterial.roughness = 0.34
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
        var backMaterial = PhysicallyBasedMaterial()
        backMaterial.baseColor = .init(tint: bodyColor)
        backMaterial.metallic = 0.55
        backMaterial.roughness = 0.30
        backMaterial.clearcoat = .init(floatLiteral: 1.0)
        backMaterial.clearcoatRoughness = .init(floatLiteral: 0.12)
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

        // Screen: emissive so state reads even against a dark field.
        var screenMaterial = PhysicallyBasedMaterial()
        screenMaterial.baseColor = .init(tint: screenColor.withAlphaComponent(0.9))
        screenMaterial.roughness = 0.14
        screenMaterial.metallic = 0.0
        screenMaterial.emissiveColor = .init(color: screenColor)
        screenMaterial.emissiveIntensity = appearance.usesLiveScreen ? 1.6 : 1.1
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

        var islandMaterial = PhysicallyBasedMaterial()
        islandMaterial.baseColor = .init(tint: edgeColor)
        islandMaterial.metallic = 0.85
        islandMaterial.roughness = 0.40
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

        var lensMaterial = PhysicallyBasedMaterial()
        lensMaterial.baseColor = .init(tint: UIColor(white: 0.04, alpha: 1))
        lensMaterial.metallic = 0.2
        lensMaterial.roughness = 0.05
        lensMaterial.clearcoat = .init(floatLiteral: 1.0)

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

    private static func uiColor(_ value: CosmeticOption.ColorValue) -> UIColor {
        UIColor(
            red: CGFloat(value.red),
            green: CGFloat(value.green),
            blue: CGFloat(value.blue),
            alpha: 1
        )
    }
}
