import Foundation
import KamikazeMotionCore
import RealityKit
import Testing
import UIKit
@testable import Kamikaze

struct PhoneAppearanceTests {
    private let catalog = TrickCatalog.provisional(gripHand: .right)

    @MainActor
    @Test func previewIsLiveEverywhereButOnlyEquipPersists() throws {
        let suite = "PhoneAppearanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppearanceStore(defaults: defaults)
        #expect(store.effective == .default)

        store.previewChange { $0.bodyID = "body-ion" }
        #expect(store.effective.bodyID == "body-ion")
        #expect(store.equipped.bodyID == "body-graphite")
        #expect(store.hasPendingPreview)

        // Discard restores the equipped phone.
        store.discardPreview()
        #expect(store.effective.bodyID == "body-graphite")

        // Equip commits and survives a cold relaunch.
        store.previewChange { $0.bodyID = "body-ion" }
        store.previewChange { $0.formFactor = .proMax }
        store.equipPreview()
        #expect(!store.hasPendingPreview)

        let reloaded = AppearanceStore(defaults: defaults)
        #expect(reloaded.equipped.bodyID == "body-ion")
        #expect(reloaded.equipped.formFactor == .proMax)
    }

    @Test func masteryGatedCosmeticsFollowPracticeProgress() throws {
        let voltBody = try #require(CosmeticCatalog.body(id: "body-volt"))
        let freeBody = try #require(CosmeticCatalog.body(id: "body-graphite"))

        let empty = PracticeProgress(summaries: [])
        #expect(CosmeticCatalog.isUnlocked(freeBody, progress: empty))
        #expect(!CosmeticCatalog.isUnlocked(voltBody, progress: empty))
        #expect(CosmeticCatalog.unlockLabel(for: voltBody) == "MASTER FLIP")

        // Mastering pair 3 (FLIP) unlocks the Volt body.
        var rows: [AttemptSummaryV1] = []
        var second = 90
        for trick in [BuiltInTrickID.flip, .reverseFlip] {
            for index in 0 ..< 3 {
                rows.append(try summary(id: "u-\(trick.rawValue)-\(index)", second: second, trick: trick))
                second -= 1
            }
        }
        let mastered = PracticeProgress(summaries: rows)
        #expect(CosmeticCatalog.isUnlocked(voltBody, progress: mastered))
    }

    @MainActor
    @Test func factoryBuildsNamedPartsPerFormFactor() {
        let plus = PhoneModelFactory.makePhone(appearance: .default, accent: .blue)
        let names = Set(collectNames(plus))
        for expected in [
            "phone-frame", "phone-back", "phone-screen",
            "phone-camera-island", "phone-camera-plate",
            "phone-button-power", "phone-button-volume-up", "phone-button-volume-down",
            "phone-camera-lens-0", "phone-camera-lens-1",
        ] {
            #expect(names.contains(expected), "missing \(expected)")
        }
        #expect(!names.contains("phone-camera-lens-2"))

        var proMaxAppearance = PhoneAppearance.default
        proMaxAppearance.formFactor = .proMax
        let proMax = PhoneModelFactory.makePhone(appearance: proMaxAppearance, accent: .blue)
        #expect(collectNames(proMax).contains("phone-camera-lens-2"))
    }

    // MARK: - Helpers

    @MainActor
    private func collectNames(_ entity: Entity) -> [String] {
        [entity.name] + entity.children.flatMap { collectNames($0) }
    }

    private func summary(id: String, second: Int, trick: BuiltInTrickID) throws -> AttemptSummaryV1 {
        let capture = try TestCaptureFactory.makeCapture(id: id, timestamp: Double(second))
        let result = TrickMatchResult(
            status: .recognized,
            policyVersion: TrickMatchingPolicy.provisionalVersion,
            catalogVersion: catalog.version,
            features: nil,
            featureIssues: [],
            candidates: [TrickMatchCandidate(
                definition: TrickDefinition(
                    id: trick,
                    displayName: trick.displayName,
                    family: .flip,
                    targetRotationDegrees: Vector3(x: 0, y: 360, z: 0),
                    referenceDurationMs: 700
                ),
                presentationFit: 0.9,
                rotationFit: 0.9,
                axisPurity: 0.8,
                durationFit: 0.8,
                minimumAxisCoverage: 1,
                axesAreSeparable: true
            )]
        )
        return AttemptSummaryV1(
            attempt: capture.attempt,
            analysis: AttemptAnalysisRecord(
                attemptID: id,
                result: result,
                humanReview: HumanAttemptReview(trickID: trick, outcome: .landed)
            )
        )
    }
}
