import Foundation

/// How you want to talk to a session. The choice is global, not per session.
public enum TalkMode: String, CaseIterable, Sendable {
    case hold
    case toggle

    public var label: String { self == .hold ? "Hold to talk" : "Tap to talk" }
}

/// Which sessions you care about, which you never want to see, and how the button behaves.
/// Keyed by session name, not id: a session that restarts keeps its name but gets a new id.
public struct Preferences: Equatable, Sendable {
    public var favorites: Set<String>
    public var hidden: Set<String>
    public var talkMode: TalkMode

    public init(favorites: Set<String> = [], hidden: Set<String> = [], talkMode: TalkMode = .hold) {
        self.favorites = favorites
        self.hidden = hidden
        self.talkMode = talkMode
    }

    public func isFavorite(_ name: String) -> Bool { favorites.contains(name) }
    public func isHidden(_ name: String) -> Bool { hidden.contains(name) }

    public mutating func toggleFavorite(_ name: String) {
        favorites.formSymmetricDifference([name])
    }

    public mutating func setHidden(_ name: String, _ hide: Bool) {
        if hide {
            hidden.insert(name)
            favorites.remove(name)
        } else {
            hidden.remove(name)
        }
    }

    // MARK: - storage

    private static let favoritesKey = "deckhand.favorites"
    private static let hiddenKey = "deckhand.hidden"
    private static let modeKey = "deckhand.talkMode"

    public static func load(from defaults: UserDefaults = .standard) -> Preferences {
        Preferences(
            favorites: Set(defaults.stringArray(forKey: favoritesKey) ?? []),
            hidden: Set(defaults.stringArray(forKey: hiddenKey) ?? []),
            talkMode: TalkMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .hold
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(Array(favorites), forKey: Self.favoritesKey)
        defaults.set(Array(hidden), forKey: Self.hiddenKey)
        defaults.set(talkMode.rawValue, forKey: Self.modeKey)
    }
}
