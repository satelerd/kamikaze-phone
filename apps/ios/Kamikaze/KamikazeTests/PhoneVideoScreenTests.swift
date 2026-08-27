import RealityKit
import Testing
import UIKit
@testable import Kamikaze

@MainActor
struct PhoneVideoScreenTests {
    @Test
    func applyingVideoChangesMaterialButNeverScreenGeometry() {
        var appearance = PhoneAppearance.default
        appearance.formFactor = .plus
        let phone = PhoneModelFactory.makePhone(
            appearance: appearance,
            accent: .systemBlue
        )
        let screen = phone.findEntity(named: "phone-screen")
        let originalTransform = screen?.transform

        PhoneModelFactory.applyScreenMaterial(
            to: phone,
            material: UnlitMaterial(color: .systemPink)
        )

        #expect(screen?.transform == originalTransform)
        #expect(phone.findEntity(named: "video-screen-rotated-180") == nil)
        #expect(phone.findEntity(named: "phone-video-overlay") == nil)
    }

    @Test
    func importedDisplayIsUpdatedWithoutTouchingItsBorder() {
        let phone = Entity()
        let screen = ModelEntity(
            mesh: .generatePlane(width: 0.07, height: 0.14),
            materials: [SimpleMaterial(color: .black, isMetallic: false)]
        )
        screen.name = "Cube_screen_0"
        let border = ModelEntity(
            mesh: .generatePlane(width: 0.08, height: 0.15),
            materials: [SimpleMaterial(color: .gray, isMetallic: true)]
        )
        border.name = "Cube_screen_border_0"
        phone.addChild(screen)
        phone.addChild(border)
        let screenTransform = screen.transform
        let borderTransform = border.transform

        PhoneModelFactory.applyScreenMaterial(
            to: phone,
            material: UnlitMaterial(color: .systemPink)
        )

        #expect(screen.model?.materials.first is UnlitMaterial)
        #expect(border.model?.materials.first is SimpleMaterial)
        #expect(screen.transform == screenTransform)
        #expect(border.transform == borderTransform)
    }

    @Test
    func pixelAndIPhone17DisplayNamesReceiveScreenMaterial() {
        for displayName in ["Plane_main_screen_0", "Cube_010_screen_001_0"] {
            let phone = Entity()
            let screen = ModelEntity(
                mesh: .generatePlane(width: 0.07, height: 0.14),
                materials: [SimpleMaterial(color: .black, isMetallic: false)]
            )
            screen.name = displayName
            phone.addChild(screen)

            PhoneModelFactory.applyScreenMaterial(
                to: phone,
                material: UnlitMaterial(color: .systemGreen)
            )

            #expect(screen.model?.materials.first is UnlitMaterial)
        }
    }
}
