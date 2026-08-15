import KamikazeMotionCore
import RealityKit
import SwiftUI

/// The 3D scene is orientation-only. A phone remains at the origin because
/// motion samples do not make a truthful enough position trajectory.
struct ReplayPhoneScene: View {
    @Bindable var controller: ReplayController
    let accent: Color
    /// Mathematical TARGET frames. When present, a translucent ghost phone
    /// plays the idealized motion phase-locked to the measured playhead. It
    /// tucks inside the measured phone when the player is on target.
    var targetFrames: [ReplayFrame]? = nil
    /// Fixed appearance for demo/target contexts; nil renders the player's
    /// equipped (or previewed) phone.
    var appearanceOverride: PhoneAppearance? = nil
    /// Screen stamp for demo phones (e.g. "IDEAL").
    var screenLabel: String? = nil

    @Environment(AppearanceStore.self) private var appearance
    @State private var previousDragTranslation = CGSize.zero
    @State private var magnifyOrigin = 1.0

    var body: some View {
        RealityView { content in
            let phone = PhoneModelFactory.makePhone(
                appearance: appearanceOverride ?? appearance.effective,
                accent: UIColor(accent),
                screenLabel: screenLabel
            )
            phone.name = "replay-phone"
            content.add(phone)
            content.add(PhoneModelFactory.makeLightRig())

            if targetFrames?.isEmpty == false {
                // The ghost IS the demo phone: distinct body and a stamped
                // IDEAL screen, never the player's configuration.
                let ghost = PhoneModelFactory.makePhone(
                    appearance: .demo,
                    accent: UIColor(KamikazeTheme.volt),
                    screenLabel: "IDEAL"
                )
                ghost.name = "target-ghost"
                ghost.scale = SIMD3(repeating: 0.97)
                ghost.components.set(OpacityComponent(opacity: 0.32))
                content.add(ghost)
            }

            let camera = PerspectiveCamera()
            camera.name = "replay-camera"
            content.add(camera)
            content.camera = .virtual
        } update: { content in
            guard let phone = content.entities.first(where: { $0.name == "replay-phone" }),
                  let camera = content.entities.first(where: { $0.name == "replay-camera" }) else { return }

            let attitude = controller.displayFrame.quaternion
            phone.orientation = simd_quatf(
                ix: Float(attitude.x), iy: Float(attitude.y), iz: Float(attitude.z), r: Float(attitude.w)
            )
            phone.position = .zero

            if let targetFrames, !targetFrames.isEmpty,
               let ghost = content.entities.first(where: { $0.name == "target-ghost" }) {
                // Phase-locked: the ghost follows the measured PROGRESS, so
                // target and measured stay comparable even when their
                // durations differ.
                let targetDuration = targetFrames.last?.timestampMs ?? 0
                let ghostFrame = ReplayBuilder.sample(targetFrames, at: controller.progress * targetDuration)
                ghost.orientation = simd_quatf(
                    ix: Float(ghostFrame.quaternion.x),
                    iy: Float(ghostFrame.quaternion.y),
                    iz: Float(ghostFrame.quaternion.z),
                    r: Float(ghostFrame.quaternion.w)
                )
                ghost.position = .zero
            }

            let rig = controller.camera
            let distance = Float(rig.distance)
            let yaw = Float(rig.azimuth)
            let pitch = Float(rig.elevation)
            camera.position = SIMD3(
                distance * sin(yaw) * cos(pitch),
                distance * sin(pitch),
                distance * cos(yaw) * cos(pitch)
            )
            camera.look(at: .zero, from: camera.position, relativeTo: nil)
        }
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture, including: .all)
        .simultaneousGesture(magnifyGesture, including: .all)
        .accessibilityLabel(targetFrames == nil ? "Replay 3D phone" : "Replay 3D phone with target ghost")
        .accessibilityHint("Drag to orbit the camera. Pinch to zoom.")
        .id(appearanceOverride ?? appearance.effective)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                controller.orbit(
                    deltaX: Double(value.translation.width - previousDragTranslation.width),
                    deltaY: Double(value.translation.height - previousDragTranslation.height)
                )
                previousDragTranslation = value.translation
            }
            .onEnded { _ in previousDragTranslation = .zero }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / magnifyOrigin
                magnifyOrigin = value.magnification
                controller.zoom(magnification: delta)
            }
            .onEnded { _ in magnifyOrigin = 1 }
    }

}

/// A reusable stage with transport and camera/reference controls. Screens may
/// embed this directly, or compose `ReplayPhoneScene` with their own result UI.
struct ReplayPhoneView: View {
    @Bindable var controller: ReplayController
    let accent: Color
    let targetFrames: [ReplayFrame]?

    init(
        controller: ReplayController,
        accent: Color = .blue,
        targetFrames: [ReplayFrame]? = nil
    ) {
        self.controller = controller
        self.accent = accent
        self.targetFrames = targetFrames
    }

    var body: some View {
        GlassCluster(spacing: 12) {
            VStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    ReplayPhoneScene(controller: controller, accent: accent, targetFrames: targetFrames)
                        .frame(minHeight: 300)
                        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                    if targetFrames != nil {
                        Text("GHOST = TARGET")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(KamikazeTheme.volt)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    HStack(spacing: 8) {
                        Button("Reset camera", systemImage: "view.3d") { controller.resetCamera() }
                            .labelStyle(.iconOnly)
                            .adaptiveGlassButton()
                        Button("Zero pose", systemImage: "scope") { controller.zeroPose() }
                            .labelStyle(.iconOnly)
                            .adaptiveGlassButton()
                    }
                    .padding(12)
                }

                // One glass surface for the whole playback tool cluster —
                // never one capsule per control.
                GlassSurface(role: .transport, cornerRadius: 24) {
                    HStack(spacing: 12) {
                        Button {
                            controller.togglePlayback()
                        } label: {
                            Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(accent)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(controller.state == .playing ? "Pause replay" : "Play replay")

                        Slider(
                            value: Binding(
                                get: { controller.progress },
                                set: { controller.seek(toProgress: $0) }
                            ),
                            in: 0 ... 1
                        )
                        .tint(accent)
                        .accessibilityLabel("Replay position")

                        Menu(controller.speed.label) {
                            ForEach(ReplayController.PlaybackSpeed.allCases) { speed in
                                Button(speed.label) { controller.setSpeed(speed) }
                            }
                        }
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .frame(minWidth: 44, minHeight: 40)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
            }
        }
    }
}
