import Foundation
import Observation
import SwiftUI

/// Cosmetic form families. Gameplay math never changes with the cosmetic
/// model; geometry is authored per family in `DeviceShapeDefinition`.
nonisolated enum PhoneFormFactor: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    // Legacy procedural IDs remain decodable so existing players never lose
    // their equipped appearance after the catalog becomes model-specific.
    case compact
    case standard
    case plus
    case proMax = "pro-max"
    case iPhone15 = "iphone-15"
    case iPhone15Plus = "iphone-15-plus"
    case iPhone15Pro = "iphone-15-pro"
    case iPhone15ProMax = "iphone-15-pro-max"
    case iPhone16 = "iphone-16"
    case iPhone16Plus = "iphone-16-plus"
    case iPhone16Pro = "iphone-16-pro"
    case iPhone16ProMax = "iphone-16-pro-max"
    case iPhone17 = "iphone-17"
    case iPhoneAir = "iphone-air"
    case iPhone17Pro = "iphone-17-pro"
    case iPhone17ProMax = "iphone-17-pro-max"
    /// Detailed CC BY asset by MajdyModels. Kept separate from the procedural
    /// shape so players can always return to the lightweight live model.
    case iPhone17ProMaxReal = "iphone-17-pro-max-real"
    /// Low-poly CC BY Google Pixel 8 Pro asset by LagzDesign.
    case pixel8Pro = "pixel-8-pro"
    case androidGeneric = "android-generic"
    /// Scanned iPhone 15 Pro Max asset (MajdyModels, CC BY 4.0 via
    /// Sketchfab). Renders the real geometry; body/edge cosmetics do not
    /// apply to it — its baked titanium textures are the look.
    case real
    /// Low-poly iPhone 15 Pro Max asset (LagzDesign, CC BY via Sketchfab).
    /// Its flat-color materials take the body/edge cosmetics, so this is the
    /// real silhouette players can paint.
    case paint = "paint-15"

    var id: String { rawValue }

    /// Player-facing catalog. Generic v1 bodies are intentionally omitted but
    /// remain supported for persisted saves.
    static let selectableCases: [PhoneFormFactor] = [
        .real, .paint, .iPhone17ProMaxReal, .pixel8Pro,
        // One deliberately rough procedural easter egg. The generated
        // pseudo-device family is no longer presented as real hardware.
        .iPhone15Pro,
    ]

    var displayName: String {
        switch self {
        case .compact: "COMPACT"
        case .standard: "STANDARD"
        case .plus: "PLUS"
        case .proMax: "PRO MAX"
        case .iPhone15: "IPHONE 15"
        case .iPhone15Plus: "15 PLUS"
        case .iPhone15Pro: "SLOPPY PHONE"
        case .iPhone15ProMax: "15 PRO MAX"
        case .iPhone16: "IPHONE 16"
        case .iPhone16Plus: "16 PLUS"
        case .iPhone16Pro: "16 PRO"
        case .iPhone16ProMax: "16 PRO MAX"
        case .iPhone17: "IPHONE 17"
        case .iPhoneAir: "IPHONE AIR"
        case .iPhone17Pro: "17 PRO"
        case .iPhone17ProMax: "17 PRO MAX"
        case .iPhone17ProMaxReal: "17 PRO MAX · REAL"
        case .pixel8Pro: "PIXEL 8 PRO · REAL"
        case .androidGeneric: "ANDROID"
        case .real: "15 PRO MAX · REAL"
        case .paint: "15 PRO MAX · PAINT"
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
        case .iPhone15:
            scaled(widthMM: 71.6, heightMM: 147.6, depthMM: 7.80, lenses: 2)
        case .iPhone15Plus:
            scaled(widthMM: 77.8, heightMM: 160.9, depthMM: 7.80, lenses: 2)
        case .iPhone15Pro:
            scaled(widthMM: 70.6, heightMM: 146.6, depthMM: 8.25, lenses: 3)
        case .iPhone15ProMax:
            scaled(widthMM: 76.7, heightMM: 159.9, depthMM: 8.25, lenses: 3)
        case .iPhone16:
            scaled(widthMM: 71.6, heightMM: 147.6, depthMM: 7.80, lenses: 2)
        case .iPhone16Plus:
            scaled(widthMM: 77.8, heightMM: 160.9, depthMM: 7.80, lenses: 2)
        case .iPhone16Pro:
            scaled(widthMM: 71.5, heightMM: 149.6, depthMM: 8.25, lenses: 3)
        case .iPhone16ProMax:
            scaled(widthMM: 77.6, heightMM: 163.0, depthMM: 8.25, lenses: 3)
        case .iPhone17:
            scaled(widthMM: 71.5, heightMM: 149.6, depthMM: 7.95, lenses: 2)
        case .iPhoneAir:
            scaled(widthMM: 74.7, heightMM: 156.2, depthMM: 5.64, lenses: 1)
        case .iPhone17Pro:
            scaled(widthMM: 71.9, heightMM: 150.0, depthMM: 8.75, lenses: 3)
        case .iPhone17ProMax:
            scaled(widthMM: 78.0, heightMM: 163.4, depthMM: 8.75, lenses: 3)
        case .iPhone17ProMaxReal:
            scaled(widthMM: 78.0, heightMM: 163.4, depthMM: 8.75, lenses: 3)
        case .pixel8Pro:
            scaled(widthMM: 76.5, heightMM: 162.6, depthMM: 8.8, lenses: 3)
        case .androidGeneric:
            scaled(widthMM: 75.0, heightMM: 162.0, depthMM: 8.6, lenses: 3)
        }
    }

    /// RealityKit stages use an authored display scale rather than physical
    /// meters; keeping one scale preserves the framing validated on device.
    private static func scaled(
        widthMM: Float,
        heightMM: Float,
        depthMM: Float,
        lenses: Int
    ) -> DeviceShapeDefinition {
        let scale: Float = 1.70 / 1_000
        return DeviceShapeDefinition(
            width: widthMM * scale,
            height: heightMM * scale,
            depth: depthMM * scale,
            cornerRadius: min(widthMM, heightMM) * scale * 0.19,
            cameraLensCount: lenses
        )
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
    struct ColorValue: Codable, Hashable, Sendable {
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
    var formFactor: PhoneFormFactor = .real
    var bodyID = "body-graphite"
    var edgeID = "edge-steel"
    var screenID = "screen-live"
    /// Optional player-authored colors. Preset IDs remain canonical so old
    /// saves decode unchanged and selecting a preset can return to an authored
    /// combination without losing catalog semantics.
    var customBodyColor: CosmeticOption.ColorValue?
    var customEdgeColor: CosmeticOption.ColorValue?
    var customScreenColor: CosmeticOption.ColorValue?

    static let `default` = PhoneAppearance()

    /// The demonstration phone used by Practice targets: deliberately NOT a
    /// configurable combination, so the demo never looks like the player's
    /// own phone.
    static let demo = PhoneAppearance(
        formFactor: .paint,
        bodyID: "body-frost",
        edgeID: "edge-volt",
        screenID: "screen-frost"
    )

    var body: CosmeticOption { CosmeticCatalog.body(id: bodyID) ?? CosmeticCatalog.bodies[0] }
    var edge: CosmeticOption { CosmeticCatalog.edge(id: edgeID) ?? CosmeticCatalog.edges[0] }
    var screen: CosmeticOption { CosmeticCatalog.screen(id: screenID) ?? CosmeticCatalog.screens[0] }
    var bodyColor: CosmeticOption.ColorValue { customBodyColor ?? body.color }
    var edgeColor: CosmeticOption.ColorValue { customEdgeColor ?? edge.color }
    var screenColor: CosmeticOption.ColorValue { customScreenColor ?? screen.color }
    /// The LIVE screen renders the gameplay accent; fixed themes render their
    /// authored emissive color.
    var usesLiveScreen: Bool { screenID == "screen-live" && customScreenColor == nil }
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
