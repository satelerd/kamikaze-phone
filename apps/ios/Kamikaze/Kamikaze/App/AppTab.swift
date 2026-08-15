import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case play
    case practice
    case locker
    case profile

    /// Debug/testing affordance: launching with `-debugInitialTab profile`
    /// opens that tab directly (standard UserDefaults argument domain).
    static var initialTab: AppTab {
        UserDefaults.standard.string(forKey: "debugInitialTab").flatMap(AppTab.init) ?? .play
    }

    var title: String {
        switch self {
        case .play: "PLAY"
        case .practice: "PRACTICE"
        case .locker: "LOCKER"
        case .profile: "ME"
        }
    }

    var symbol: String {
        switch self {
        case .play: "arrow.trianglehead.2.clockwise.rotate.90"
        case .practice: "figure.skateboarding"
        case .locker: "square.3.layers.3d"
        case .profile: "person.crop.circle"
        }
    }
}
