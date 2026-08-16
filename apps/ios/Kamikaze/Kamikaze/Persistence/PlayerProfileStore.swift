import Foundation
import Observation

/// Local player identity. No account, no cloud: a display name and the date
/// the player started, kept in UserDefaults. Attempt IDs never depend on it.
@MainActor
@Observable
final class PlayerProfileStore {
    private enum Key {
        static let name = "playerName"
        static let joinedAt = "playerJoinedAtISO8601"
    }

    static let defaultName = "RIDER"
    static let maximumNameLength = 18

    private let defaults: UserDefaults

    private(set) var name: String
    private(set) var joinedAtISO8601: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedName = defaults.string(forKey: Key.name)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        name = (storedName?.isEmpty == false ? storedName! : Self.defaultName)
        if let joined = defaults.string(forKey: Key.joinedAt) {
            joinedAtISO8601 = joined
        } else {
            let now = ISO8601DateFormatter().string(from: Date())
            defaults.set(now, forKey: Key.joinedAt)
            joinedAtISO8601 = now
        }
    }

    var joinedLabel: String {
        guard let date = ISO8601DateFormatter().date(from: joinedAtISO8601) else { return "" }
        return "RIDING SINCE \(date.formatted(.dateTime.month(.abbreviated).year()).uppercased())"
    }

    func rename(to newName: String) {
        let cleaned = newName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.maximumNameLength)
        guard !cleaned.isEmpty else { return }
        name = String(cleaned).uppercased()
        defaults.set(name, forKey: Key.name)
    }
}
