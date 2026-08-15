import KamikazeMotionCore
import RealityKit
import SwiftUI

/// Stamps the configuration a phone entity was built with, so scene updates
/// can swap the entity in place. Recreating the whole RealityView (the old
/// `.id()` approach) re-triggers a device-only black-render path — entities
/// are replaced inside the running scene instead.
struct AppearanceStampComponent: Component {
    var appearance: PhoneAppearance
    var accentDescription: String
}

enum PhoneSceneRefresher {
    /// Replaces a scene's phone when its stamped configuration is stale.
    /// Cheap when nothing changed: one Equatable comparison per update.
    @MainActor
    @discardableResult
    static func refreshPhone(
        in content: inout RealityViewCameraContent,
        named name: String,
        appearance: PhoneAppearance,
        accent: UIColor,
        screenLabel: String? = nil,
        configure: ((Entity) -> Void)? = nil
    ) -> Entity? {
        let current = content.entities.first(where: { $0.name == name })
        let stamp = current?.components[AppearanceStampComponent.self]
        let accentKey = accent.description
        if let current, let stamp,
           stamp.appearance == appearance, stamp.accentDescription == accentKey {
            return current
        }
        let previousOrientation = current?.orientation
        if let current {
            content.remove(current)
        }
        let phone = PhoneModelFactory.makePhone(
            appearance: appearance,
            accent: accent,
            screenLabel: screenLabel
        )
        phone.name = name
        phone.components.set(AppearanceStampComponent(
            appearance: appearance,
            accentDescription: accentKey
        ))
        if let previousOrientation {
            phone.orientation = previousOrientation
        }
        configure?(phone)
        content.add(phone)
        return phone
    }
}

struct LivePhoneScene: View {
    let attitude: Quaternion
    let accent: Color
    /// Authored showcase camera, used by Setup so the phone presents its
    /// depth, frame and camera island instead of a flat front view.
    var initialYaw = 0.0
    var initialPitch = 0.0
    let initialZoom: Double
    /// When provided, the stage shows the LEVEL control next to CAMERA.
    var onLevel: (() -> Void)?

    @Environment(AppearanceStore.self) private var appearance
    @State private var orbitYaw: Double
    @State private var orbitPitch: Double
    @State private var zoom: Double
    @State private var dragOrigin: (yaw: Double, pitch: Double)?
    @State private var magnifyOrigin: Double?

    init(
        attitude: Quaternion,
        accent: Color,
        initialYaw: Double = 0,
        initialPitch: Double = 0,
        initialZoom: Double = 0.72,
        onLevel: (() -> Void)? = nil
    ) {
        self.attitude = attitude
        self.accent = accent
        self.initialYaw = initialYaw
        self.initialPitch = initialPitch
        self.initialZoom = initialZoom
        self.onLevel = onLevel
        _orbitYaw = State(initialValue: initialYaw)
        _orbitPitch = State(initialValue: initialPitch)
        _zoom = State(initialValue: initialZoom)
    }

    var body: some View {
        RealityView { content in
            PhoneSceneRefresher.refreshPhone(
                in: &content,
                named: "phone",
                appearance: appearance.effective,
                accent: UIColor(accent)
            )
            content.add(PhoneModelFactory.makeLightRig())

            let camera = PerspectiveCamera()
            camera.name = "camera"
            content.add(camera)
            content.camera = .virtual
        } update: { content in
            let phone = PhoneSceneRefresher.refreshPhone(
                in: &content,
                named: "phone",
                appearance: appearance.effective,
                accent: UIColor(accent)
            )
            phone?.orientation = simd_quatf(
                ix: Float(attitude.x),
                iy: Float(attitude.y),
                iz: Float(attitude.z),
                r: Float(attitude.w)
            )
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
            // The stage's two controls live together: LEVEL sets the neutral
            // grip, CAMERA restores the viewing angle.
            HStack(spacing: 8) {
                if let onLevel {
                    Button {
                        onLevel()
                    } label: {
                        Label("LEVEL", systemImage: "level")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .adaptiveGlassButton()
                    .accessibilityHint("Sets the current grip as the phone's neutral pose")
                }
                Button {
                    withAnimation(.snappy) {
                        orbitYaw = initialYaw
                        orbitPitch = initialPitch
                        zoom = initialZoom
                    }
                } label: {
                    Label("CAMERA", systemImage: "camera")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .adaptiveGlassButton()
                .accessibilityHint("Resets the viewing camera")
            }
            .padding(12)
        }
        .accessibilityLabel("Live 3D phone pose")
    }
}
