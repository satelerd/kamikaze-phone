import Foundation
import Observation
import SwiftUI

/// Cosmetic form families. Gameplay math never changes with the cosmetic
/// model; geometry is authored per family in `DeviceShapeDefinition`.
nonisolated enum PhoneFormFactor: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case compact
    case standard
    case plus
    case proMax = "pro-max"
    /// Scanned iPhone 15 Pro Max asset (MajdyModels, CC BY 4.0 via
    /// Sketchfab). Renders the real geometry; body/edge cosmetics do not
    /// apply to it — its baked titanium textures are the look.
    case real
    /// Low-poly iPhone 15 Pro Max asset (LagzDesign, CC BY via Sketchfab).
    /// Its flat-color materials take the body/edge cosmetics, so this is the
    /// real silhouette players can paint.
    case paint = "paint-15"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: "COMPACT"
        case .standard: "STANDARD"
        case .plus: "PLUS"
        case .proMax: "PRO MAX"
        case .real: "REAL 15 PRO"
        case .paint: "PAINT 15"
        }
    }
}

/// Versioned authored geometry: portrait meters, centered pivot. Reference
/// family is the iPhone 15 Plus-class body the detector was validated on.
nonisolated struct DeviceShapeDefinition: Equatable, Sendable {
    static let version = 1

    let width: Float
    let height: Float
    let depth: Float
    let cornerRadius: Float
    let cameraLensCount: Int

    static func shape(for formFactor: PhoneFormFactor) -> DeviceShapeDefinition {
        switch formFactor {
        case .compact:
            DeviceShapeDefinition(width: 0.1176, height: 0.2436, depth: 0.0148, cornerRadius: 0.022, cameraLensCount: 2)
        case .standard:
            DeviceShapeDefinition(width: 0.1234, height: 0.2554, depth: 0.0156, cornerRadius: 0.024, cameraLensCount: 2)
        case .plus:
            DeviceShapeDefinition(width: 0.1320, height: 0.2730, depth: 0.0156, cornerRadius: 0.026, cameraLensCount: 2)
        case .proMax, .real, .paint:
            DeviceShapeDefinition(width: 0.1340, height: 0.2772, depth: 0.0166, cornerRadius: 0.027, cameraLensCount: 3)
        }
    }
}

/// Authored cosmetic choices. Persist IDs, never colors: authored combinations
/// keep rewards recognizable and the phone legible in every field state.
nonisolated struct CosmeticOption: Equatable, Sendable, Identifiable {
    enum Unlock: Equatable, Sendable {
        case free
        /// Unlocked by mastering the given practice pair (order number).
        case masterPair(Int)
    }

    let id: String
    let displayName: String
    let color: ColorValue
    let unlock: Unlock

    /// sRGB triple so options stay Codable-friendly and testable.
    struct ColorValue: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }
    }
}

nonisolated enum CosmeticCatalog {
    static let version = "cosmetic-catalog-v1"

    static let bodies: [CosmeticOption] = [
        CosmeticOption(id: "body-graphite", displayName: "GRAPHITE", color: .init(red: 0.13, green: 0.14, blue: 0.14), unlock: .free),
        CosmeticOption(id: "body-frost", displayName: "FROST", color: .init(red: 0.78, green: 0.80, blue: 0.82), unlock: .free),
        CosmeticOption(id: "body-ion", displayName: "ION", color: .init(red: 0.22, green: 0.28, blue: 0.62), unlock: .free),
        CosmeticOption(id: "body-hazard", displayName: "HAZARD", color: .init(red: 0.72, green: 0.24, blue: 0.18), unlock: .masterPair(2)),
        CosmeticOption(id: "body-volt", displayName: "VOLT", color: .init(red: 0.62, green: 0.76, blue: 0.16), unlock: .masterPair(3)),
    ]

    static let edges: [CosmeticOption] = [
        CosmeticOption(id: "edge-steel", displayName: "STEEL", color: .init(red: 0.62, green: 0.64, blue: 0.66), unlock: .free),
        CosmeticOption(id: "edge-black", displayName: "BLACK", color: .init(red: 0.08, green: 0.08, blue: 0.09), unlock: .free),
        CosmeticOption(id: "edge-volt", displayName: "VOLT RAIL", color: .init(red: 0.74, green: 0.90, blue: 0.22), unlock: .masterPair(2)),
    ]

    static let screens: [CosmeticOption] = [
        // "LIVE" keeps the gameplay-accent emissive screen; state stays visible.
        CosmeticOption(id: "screen-live", displayName: "LIVE STATE", color: .init(red: 0.30, green: 0.40, blue: 1.00), unlock: .free),
        CosmeticOption(id: "screen-pitch", displayName: "BLACKOUT", color: .init(red: 0.05, green: 0.06, blue: 0.06), unlock: .free),
        CosmeticOption(id: "screen-frost", displayName: "PAPER", color: .init(red: 0.86, green: 0.88, blue: 0.90), unlock: .masterPair(5)),
        // The player's own image (CustomScreenStore); falls back to BLACKOUT
        // until a photo is chosen.
        CosmeticOption(id: "screen-photo", displayName: "PHOTO", color: .init(red: 0.10, green: 0.11, blue: 0.13), unlock: .free),
    ]

    static func body(id: String) -> CosmeticOption? { bodies.first { $0.id == id } }
    static func edge(id: String) -> CosmeticOption? { edges.first { $0.id == id } }
    static func screen(id: String) -> CosmeticOption? { screens.first { $0.id == id } }

    static func isUnlocked(_ option: CosmeticOption, progress: PracticeProgress) -> Bool {
        switch option.unlock {
        case .free:
            return true
        case let .masterPair(order):
            guard let pair = PracticeLibrary.pairs.first(where: { $0.order == order }) else { return false }
            return progress.isPairMastered(pair)
        }
    }

    static func unlockLabel(for option: CosmeticOption) -> String? {
        switch option.unlock {
        case .free:
            return nil
        case let .masterPair(order):
            let title = PracticeLibrary.pairs.first { $0.order == order }?.title ?? "PAIR \(order)"
            return "MASTER \(title)"
        }
    }
}

/// The configured phone. Only canonical IDs and the catalog version persist.
nonisolated struct PhoneAppearance: Codable, Hashable, Sendable {
    static let schemaVersion = 1

    var schemaVersion = Self.schemaVersion
    var catalogVersion = CosmeticCatalog.version
    var formFactor: PhoneFormFactor = .plus
    var bodyID = "body-graphite"
    var edgeID = "edge-steel"
    var screenID = "screen-live"

    static let `default` = PhoneAppearance()

    /// The demonstration phone used by Practice targets: deliberately NOT a
    /// configurable combination, so the demo never looks like the player's
    /// own phone.
    static let demo = PhoneAppearance(
        formFactor: .standard,
        bodyID: "body-frost",
        edgeID: "edge-volt",
        screenID: "screen-frost"
    )

    var body: CosmeticOption { CosmeticCatalog.body(id: bodyID) ?? CosmeticCatalog.bodies[0] }
    var edge: CosmeticOption { CosmeticCatalog.edge(id: edgeID) ?? CosmeticCatalog.edges[0] }
    var screen: CosmeticOption { CosmeticCatalog.screen(id: screenID) ?? CosmeticCatalog.screens[0] }
    /// The LIVE screen renders the gameplay accent; fixed themes render their
    /// authored emissive color.
    var usesLiveScreen: Bool { screenID == "screen-live" }
    /// PHOTO renders the player's own image from `CustomScreenStore`.
    var usesCustomPhotoScreen: Bool { screenID == "screen-photo" }
}

/// Persisted player choice, injected through the shell so Play, Replay,
/// Practice and Setup show the same phone immediately.
@MainActor
@Observable
final class AppearanceStore {
    private static let key = "phoneAppearance.v1"

    private let defaults: UserDefaults
    private(set) var equipped: PhoneAppearance

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(PhoneAppearance.self, from: data),
           stored.schemaVersion == PhoneAppearance.schemaVersion {
            equipped = stored
        } else {
            equipped = .default
        }
    }

    var effective: PhoneAppearance { equipped }

    /// Setup is auto-saving: every tap applies and persists immediately.
    /// There is deliberately no draft/confirm step.
    func applyChange(_ transform: (inout PhoneAppearance) -> Void) {
        var draft = equipped
        transform(&draft)
        equipped = draft
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(equipped) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
