import KamikazeMotionCore
import RealityKit
import SwiftUI

struct LivePhoneScene: View {
    let attitude: Quaternion
    let accent: Color

    @State private var orbitYaw = 0.0
    @State private var orbitPitch = 0.0
    @State private var zoom = 0.72
    @State private var dragOrigin: (yaw: Double, pitch: Double)?
    @State private var magnifyOrigin: Double?

    var body: some View {
        RealityView { content in
            let phone = makePhone()
            phone.name = "phone"
            content.add(phone)

            let camera = PerspectiveCamera()
            camera.name = "camera"
            content.add(camera)
            content.camera = .virtual
        } update: { content in
            if let phone = content.entities.first(where: { $0.name == "phone" }) {
                phone.orientation = simd_quatf(
                    ix: Float(attitude.x),
                    iy: Float(attitude.y),
                    iz: Float(attitude.z),
                    r: Float(attitude.w)
                )
            }
            if let camera = content.entities.first(where: { $0.name == "camera" }) {
                let distance = Float(zoom)
                let yaw = Float(orbitYaw)
                let pitch = Float(orbitPitch)
                camera.position = SIMD3(
                    distance * sin(yaw) * cos(pitch),
                    distance * sin(pitch),
                    distance * cos(yaw) * cos(pitch)
                )
                camera.look(at: .zero, from: camera.position, relativeTo: nil)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let origin = dragOrigin ?? (orbitYaw, orbitPitch)
                    dragOrigin = origin
                    orbitYaw = origin.yaw - value.translation.width * 0.008
                    orbitPitch = min(
                        .pi * 0.46,
                        max(-.pi * 0.46, origin.pitch + value.translation.height * 0.008)
                    )
                }
                .onEnded { _ in dragOrigin = nil }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let origin = magnifyOrigin ?? zoom
                    magnifyOrigin = origin
                    zoom = min(1.2, max(0.38, origin / value.magnification))
                }
                .onEnded { _ in magnifyOrigin = nil }
        )
        .overlay(alignment: .bottomTrailing) {
            Button("Reset camera", systemImage: "view.3d") {
                withAnimation(.snappy) {
                    orbitYaw = 0
                    orbitPitch = 0
                    zoom = 0.72
                }
            }
            .labelStyle(.iconOnly)
            .adaptiveGlassButton()
            .padding(12)
            .accessibilityLabel("Reset camera")
        }
        .accessibilityLabel("Live 3D phone pose")
    }

    private func makePhone() -> Entity {
        let root = Entity()

        let bodyMaterial = SimpleMaterial(color: .black, roughness: 0.24, isMetallic: true)
        let body = ModelEntity(
            mesh: .generateBox(width: 0.132, height: 0.27, depth: 0.016, cornerRadius: 0.026),
            materials: [bodyMaterial]
        )
        root.addChild(body)

        let screenColor = UIColor(accent).withAlphaComponent(0.84)
        let screen = ModelEntity(
            mesh: .generateBox(width: 0.119, height: 0.248, depth: 0.002, cornerRadius: 0.019),
            materials: [SimpleMaterial(color: screenColor, roughness: 0.16, isMetallic: false)]
        )
        screen.position.z = 0.009
        root.addChild(screen)

        return root
    }
}
