import KamikazeMotionCore
import RealityKit
import SwiftUI

/// The 3D scene is orientation-only. A phone remains at the origin because
/// motion samples do not make a truthful enough position trajectory.
struct ReplayPhoneScene: View {
    @Bindable var controller: ReplayController
    let accent: Color

    @State private var previousDragTranslation = CGSize.zero
    @State private var magnifyOrigin = 1.0

    var body: some View {
        RealityView { content in
            let phone = makePhone()
            phone.name = "replay-phone"
            content.add(phone)

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
        .accessibilityLabel("Replay 3D phone")
        .accessibilityHint("Drag to orbit the camera. Pinch to zoom.")
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

    private func makePhone() -> Entity {
        let root = Entity()
        let body = ModelEntity(
            mesh: .generateBox(width: 0.132, height: 0.27, depth: 0.016, cornerRadius: 0.026),
            materials: [SimpleMaterial(color: .black, roughness: 0.24, isMetallic: true)]
        )
        root.addChild(body)

        let screen = ModelEntity(
            mesh: .generateBox(width: 0.119, height: 0.248, depth: 0.002, cornerRadius: 0.019),
            materials: [SimpleMaterial(color: UIColor(accent).withAlphaComponent(0.84), roughness: 0.16, isMetallic: false)]
        )
        screen.position.z = 0.009
        root.addChild(screen)
        return root
    }
}

/// A reusable stage with transport and camera/reference controls. Screens may
/// embed this directly, or compose `ReplayPhoneScene` with their own result UI.
struct ReplayPhoneView: View {
    @Bindable var controller: ReplayController
    let accent: Color

    init(controller: ReplayController, accent: Color = .blue) {
        self.controller = controller
        self.accent = accent
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ReplayPhoneScene(controller: controller, accent: accent)
                    .frame(minHeight: 300)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                HStack(spacing: 8) {
                    Button("Reset camera", systemImage: "view.3d") { controller.resetCamera() }
                        .labelStyle(.iconOnly)
                    Button("Zero pose", systemImage: "scope") { controller.zeroPose() }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .padding(12)
            }

            HStack(spacing: 12) {
                Button {
                    controller.togglePlayback()
                } label: {
                    Image(systemName: controller.state == .playing ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(controller.state == .playing ? "Pause replay" : "Play replay")
                .buttonStyle(.borderedProminent)
                .tint(accent)

                Slider(
                    value: Binding(
                        get: { controller.progress },
                        set: { controller.seek(toProgress: $0) }
                    ),
                    in: 0 ... 1
                )
                .accessibilityLabel("Replay position")

                Menu(controller.speed.label) {
                    ForEach(ReplayController.PlaybackSpeed.allCases) { speed in
                        Button(speed.label) { controller.setSpeed(speed) }
                    }
                }
                .font(.system(.caption, design: .monospaced).weight(.bold))
            }
            .padding(.horizontal, 4)
        }
    }
}
