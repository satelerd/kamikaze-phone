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
    /// Whether this entity was built from a downloaded asset. When the async
    /// asset load lands, the flag mismatch triggers the in-place swap.
    var usedRealAsset = false
    /// CustomScreenStore revision baked into this entity, so choosing a new
    /// PHOTO screen image rebuilds live phones.
    var screenPhotoRevision = 0
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
        let wantsReal = PhoneModelFactory.usesRealAsset(for: appearance)
        let photoRevision = CustomScreenStore.shared.revision
        if let current, let stamp,
           stamp.appearance == appearance, stamp.accentDescription == accentKey,
           stamp.usedRealAsset == wantsReal, stamp.screenPhotoRevision == photoRevision {
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
            accentDescription: accentKey,
            usedRealAsset: wantsReal,
            screenPhotoRevision: photoRevision
        ))
        if let previousOrientation {
            phone.orientation = previousOrientation
        }
        configure?(phone)
        content.add(phone)
        return phone
    }
}

/// An authored viewing angle for the stage camera. Setup animates between
/// poses as the player switches cosmetic sections, so the camera frames the
/// part being edited (screen, body, edge).
struct StageCameraPose: Equatable {
    var yaw: Double
    var pitch: Double
    var zoom: Double
}

struct LivePhoneScene: View {
    let attitude: Quaternion
    let accent: Color
    /// Authored showcase camera, used by Setup so the phone presents its
    /// depth, frame and camera island instead of a flat front view.
    var initialYaw = 0.0
    var initialPitch = 0.0
    let initialZoom: Double
    /// Optional ideal pose rendered as a translucent phone in the same
    /// RealityKit scene. Used by guided calibration without a second GPU view.
    var ghostAttitude: Quaternion?
    /// External camera target. When it changes, the stage animates the orbit
    /// to the new pose (manual drags still work in between).
    var cameraPose: StageCameraPose?
    /// When provided, the stage shows the LEVEL control next to CAMERA.
    var onLevel: (() -> Void)?
    /// Optional iOS 26 live video material for Camera V2. The material is
    /// created once by the capture owner and reused across 50 Hz pose updates.
    var screenVideoMaterial: VideoMaterial?

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
        ghostAttitude: Quaternion? = nil,
        cameraPose: StageCameraPose? = nil,
        onLevel: (() -> Void)? = nil,
        screenVideoMaterial: VideoMaterial? = nil
    ) {
        self.attitude = attitude
        self.accent = accent
        self.initialYaw = cameraPose?.yaw ?? initialYaw
        self.initialPitch = cameraPose?.pitch ?? initialPitch
        self.initialZoom = cameraPose?.zoom ?? initialZoom
        self.ghostAttitude = ghostAttitude
        self.cameraPose = cameraPose
        self.onLevel = onLevel
        self.screenVideoMaterial = screenVideoMaterial
        _orbitYaw = State(initialValue: self.initialYaw)
        _orbitPitch = State(initialValue: self.initialPitch)
        _zoom = State(initialValue: self.initialZoom)
    }

    var body: some View {
        // Observation hooks: when a downloaded asset finishes loading or the
        // PHOTO screen image changes, these reads re-evaluate the view so the
        // update pass can swap the phone.
        let _ = PhoneModelLibrary.shared.loaded
        let _ = CustomScreenStore.shared.revision
        RealityView { content in
            let phone = PhoneSceneRefresher.refreshPhone(
                in: &content,
                named: "phone",
                appearance: appearance.effective,
                accent: UIColor(accent)
            )
            if let phone, let screenVideoMaterial {
                PhoneModelFactory.applyScreenMaterial(to: phone, material: screenVideoMaterial)
            }
            content.add(PhoneModelFactory.makeLightRig())

            if ghostAttitude != nil {
                let ghost = PhoneModelFactory.makePhone(
                    appearance: .demo,
                    accent: UIColor(KamikazeTheme.volt),
                    screenLabel: "FOLLOW"
                )
                ghost.name = "pose-guide-ghost"
                ghost.scale = SIMD3(repeating: 1.04)
                ghost.components.set(OpacityComponent(opacity: 0.30))
                content.add(ghost)
            }

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
            if let phone, let screenVideoMaterial {
                PhoneModelFactory.applyScreenMaterial(to: phone, material: screenVideoMaterial)
            }
            phone?.orientation = simd_quatf(
                ix: Float(attitude.x),
                iy: Float(attitude.y),
                iz: Float(attitude.z),
                r: Float(attitude.w)
            )
            if let ghostAttitude {
                let ghost: Entity
                if let existing = content.entities.first(where: { $0.name == "pose-guide-ghost" }) {
                    ghost = existing
                } else {
                    ghost = PhoneModelFactory.makePhone(
                        appearance: .demo,
                        accent: UIColor(KamikazeTheme.volt),
                        screenLabel: "FOLLOW"
                    )
                    ghost.name = "pose-guide-ghost"
                    ghost.scale = SIMD3(repeating: 1.04)
                    ghost.components.set(OpacityComponent(opacity: 0.30))
                    content.add(ghost)
                }
                ghost.orientation = simd_quatf(
                    ix: Float(ghostAttitude.x),
                    iy: Float(ghostAttitude.y),
                    iz: Float(ghostAttitude.z),
                    r: Float(ghostAttitude.w)
                )
            } else if let ghost = content.entities.first(where: { $0.name == "pose-guide-ghost" }) {
                content.remove(ghost)
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
        .onChange(of: cameraPose) { _, pose in
            guard let pose else { return }
            withAnimation(.smooth(duration: 0.55)) {
                orbitYaw = pose.yaw
                orbitPitch = pose.pitch
                zoom = pose.zoom
            }
        }
        .highPriorityGesture(
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
                .onEnded { _ in dragOrigin = nil },
            including: .all
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let origin = magnifyOrigin ?? zoom
                    magnifyOrigin = origin
                    zoom = min(1.2, max(0.18, origin / value.magnification))
                }
                .onEnded { _ in magnifyOrigin = nil }
        )
        // Label the stage BEFORE attaching the overlay: applied after, it
        // would swallow the LEVEL/CAMERA buttons out of the a11y tree.
        .accessibilityLabel("Live 3D phone pose")
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
    }
}
