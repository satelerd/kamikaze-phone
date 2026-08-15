import KamikazeMotionCore
import RealityKit
import SwiftUI

struct LivePhoneScene: View {
    let attitude: Quaternion
    let accent: Color
    /// Authored showcase camera, used by Setup so the phone presents its
    /// depth, frame and camera island instead of a flat front view.
    var initialYaw = 0.0
    var initialPitch = 0.0

    @Environment(AppearanceStore.self) private var appearance
    @State private var orbitYaw: Double
    @State private var orbitPitch: Double
    @State private var zoom = 0.72

    init(
        attitude: Quaternion,
        accent: Color,
        initialYaw: Double = 0,
        initialPitch: Double = 0
    ) {
        self.attitude = attitude
        self.accent = accent
        self.initialYaw = initialYaw
        self.initialPitch = initialPitch
        _orbitYaw = State(initialValue: initialYaw)
        _orbitPitch = State(initialValue: initialPitch)
    }
    @State private var dragOrigin: (yaw: Double, pitch: Double)?
    @State private var magnifyOrigin: Double?

    var body: some View {
        RealityView { content in
            let phone = PhoneModelFactory.makePhone(
                appearance: appearance.effective,
                accent: UIColor(accent)
            )
            phone.name = "phone"
            content.add(phone)
            content.add(PhoneModelFactory.makeLightRig())

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
                    orbitYaw = initialYaw
                    orbitPitch = initialPitch
                    zoom = 0.72
                }
            }
            .labelStyle(.iconOnly)
            .adaptiveGlassButton()
            .padding(12)
            .accessibilityLabel("Reset camera")
        }
        .accessibilityLabel("Live 3D phone pose")
        // A cosmetic change rebuilds the scene; appearance edits are rare.
        .id(appearance.effective)
    }
}
