import Foundation

/// How you want to talk to a session. The choice is global, not per session.
public enum TalkMode: String, CaseIterable, Sendable {
    case hold
    case toggle

    public var label: String { self == .hold ? "Hold to talk" : "Tap to talk" }
}

/// How a spoken message gets into the session.
public enum DeliveryRoute: String, CaseIterable, Sendable {
    /// Type it into the pane when there is one, fall back to the peer socket when there is not.
    case auto
    /// Always the keyboard. Your own words, your own authority, and nothing if iTerm is silent.
    case keyboard
    /// Always the peer socket. Never fails, but arrives marked as coming from another agent.
    case socket

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .keyboard: "Keyboard"
        case .socket: "Socket"
        }
    }

    public var explanation: String {
        switch self {
        case .auto: "Keyboard when the session has an iTerm pane, socket when it does not."
        case .keyboard: "Typed into the pane, so the session reads it as you speaking."
        case .socket: "Always delivered, but marked as coming from another Claude session."
        }
    }
}

/// Which sessions you care about, which you never want to see, and how the button behaves.
/// Keyed by session name, not id: a session that restarts keeps its name but gets a new id.
public struct Preferences: Equatable, Sendable {
    public var favorites: Set<String>
    public var hidden: Set<String>
    public var talkMode: TalkMode
    public var route: DeliveryRoute
    /// Read the transcript before it goes in. Speaking into a busy session is not undoable,
    /// so this is on until someone decides they would rather it were not.
    public var confirms: Bool

    public init(
        favorites: Set<String> = [],
        hidden: Set<String> = [],
        talkMode: TalkMode = .hold,
        route: DeliveryRoute = .auto,
        confirms: Bool = true
    ) {
        self.favorites = favorites
        self.hidden = hidden
        self.talkMode = talkMode
        self.route = route
        self.confirms = confirms
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
    private static let routeKey = "deckhand.route"
    private static let confirmsKey = "deckhand.confirms"

    public static func load(from defaults: UserDefaults = .standard) -> Preferences {
        Preferences(
            favorites: Set(defaults.stringArray(forKey: favoritesKey) ?? []),
            hidden: Set(defaults.stringArray(forKey: hiddenKey) ?? []),
            talkMode: TalkMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .hold,
            route: DeliveryRoute(rawValue: defaults.string(forKey: routeKey) ?? "") ?? .auto,
            confirms: defaults.object(forKey: confirmsKey) as? Bool ?? true
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(Array(favorites), forKey: Self.favoritesKey)
        defaults.set(Array(hidden), forKey: Self.hiddenKey)
        defaults.set(talkMode.rawValue, forKey: Self.modeKey)
        defaults.set(route.rawValue, forKey: Self.routeKey)
        defaults.set(confirms, forKey: Self.confirmsKey)
    }
}
