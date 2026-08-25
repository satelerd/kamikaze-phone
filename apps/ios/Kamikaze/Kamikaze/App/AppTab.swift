import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case play
    case practice
    case locker
    case profile
    case beta

    /// Debug/testing affordance: launching with `-debugInitialTab profile`
    /// opens that tab directly (standard UserDefaults argument domain).
    static var initialTab: AppTab {
        UserDefaults.standard.string(forKey: "debugInitialTab").flatMap(AppTab.init) ?? .play
    }

    var title: String {
        switch self {
        case .play: "PLAY"
        case .practice: "PRACTICE"
        // Player-facing label prototyped as Setup; routes and source folders
        // keep the Locker name until the label is validated.
        case .locker: "SETUP"
        case .beta: "BETA"
        case .profile: "ME"
        }
    }

    var symbol: String {
        switch self {
        case .play: "gamecontroller.fill"
        case .practice: "target"
        case .locker: "square.3.layers.3d"
        case .beta: "testtube.2"
        case .profile: "person.crop.circle"
        }
    }

    /// The field's resting accent while this tab is frontmost and no run is
    /// in progress.
    var ambientAccent: Color {
        switch self {
        case .play: KamikazeTheme.ion
        case .practice: KamikazeTheme.hazard
        case .locker: KamikazeTheme.ion
        case .beta: KamikazeTheme.hazard
        case .profile: KamikazeTheme.volt
        }
    }
}
