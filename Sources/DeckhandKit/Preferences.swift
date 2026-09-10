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
    /// Show a markdown file as a document rather than as its source.
    ///
    /// On, because the reason to open a `report.md` on a phone is to read it. It lives here
    /// rather than per file because it is a reading preference and not a property of any one
    /// file — so the next report opens in whatever was last chosen, which is the answer you
    /// wanted both times.
    public var formatsMarkdown: Bool
    /// How far back the rail draws sessions messaging each other, and — because the phone
    /// sends it to the Mac — how far back the Mac reads for them. One number for both, so the
    /// scan and the picture cannot disagree about what "lately" means.
    public var linkWindow: TimeInterval

    /// What the window may be set to. Five minutes is the middle of it and the default: long
    /// enough that a conversation is still on screen when you pick the phone up, short enough
    /// that the rail is empty most of the time. Every value is inside the daemon's own
    /// `MIN_WINDOW`/`MAX_WINDOW`, which refuses anything outside 30 s–1 h with a 422.
    public static let linkWindows: [TimeInterval] = [60, 300, 900, 1800]

    public init(
        favorites: Set<String> = [],
        hidden: Set<String> = [],
        talkMode: TalkMode = .hold,
        route: DeliveryRoute = .auto,
        confirms: Bool = true,
        formatsMarkdown: Bool = true,
        linkWindow: TimeInterval = 300
    ) {
        self.favorites = favorites
        self.hidden = hidden
        self.talkMode = talkMode
        self.route = route
        self.confirms = confirms
        self.formatsMarkdown = formatsMarkdown
        self.linkWindow = linkWindow
    }

    /// "5 min", for the picker and for the sentence under it.
    public static func windowLabel(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) s" : "\(Int(seconds / 60)) min"
    }

    public func isFavorite(_ name: String) -> Bool { favorites.contains(name) }
    public func isHidden(_ name: String) -> Bool { hidden.contains(name) }

    public mutating func toggleFavorite(_ name: String) {
        favorites.formSymmetricDifference([name])
    }

    /// Carry what you decided about a session onto its new name.
    ///
    /// These are keyed by name because a session that restarts keeps its name and gets a new
    /// id — which is the right trade until the name itself changes, and then the star has to
    /// be moved by hand or it is silently lost.
    public mutating func renamed(from old: String, to new: String) {
        if favorites.remove(old) != nil { favorites.insert(new) }
        if hidden.remove(old) != nil { hidden.insert(new) }
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
    private static let formatsKey = "deckhand.formatsMarkdown"
    private static let linkWindowKey = "deckhand.linkWindow"

    public static func load(from defaults: UserDefaults = .standard) -> Preferences {
        Preferences(
            favorites: Set(defaults.stringArray(forKey: favoritesKey) ?? []),
            hidden: Set(defaults.stringArray(forKey: hiddenKey) ?? []),
            talkMode: TalkMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .hold,
            route: DeliveryRoute(rawValue: defaults.string(forKey: routeKey) ?? "") ?? .auto,
            confirms: defaults.object(forKey: confirmsKey) as? Bool ?? true,
            // `object(forKey:)` rather than `bool(forKey:)`, because a missing key reads as
            // false and the default here is on.
            formatsMarkdown: defaults.object(forKey: formatsKey) as? Bool ?? true,
            linkWindow: defaults.object(forKey: linkWindowKey) as? TimeInterval ?? 300
        )
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(Array(favorites), forKey: Self.favoritesKey)
        defaults.set(Array(hidden), forKey: Self.hiddenKey)
        defaults.set(talkMode.rawValue, forKey: Self.modeKey)
        defaults.set(route.rawValue, forKey: Self.routeKey)
        defaults.set(confirms, forKey: Self.confirmsKey)
        defaults.set(formatsMarkdown, forKey: Self.formatsKey)
        defaults.set(linkWindow, forKey: Self.linkWindowKey)
    }
}
