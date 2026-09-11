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
///
/// Keyed by `machine/name`, not by id: a session that restarts keeps its name but gets a new id,
/// so an id-keyed star would be gone by morning. The machine half is what keeps that name
/// unambiguous — names come from the folder, so two machines produce `deckhand` without trying,
/// and starring one would silently star both. ``migrated(onto:)`` carries the names stored before
/// this existed onto the machine they were always about.
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

    /// What one session is filed under. A session with no machine on it — an older Mac's
    /// listing — keys under the bare name, which is exactly what that Mac's own store holds.
    public static func key(_ session: Session) -> String { key(session.machine, session.name) }

    public static func key(_ machine: String?, _ name: String) -> String {
        guard let machine, !machine.isEmpty else { return name }
        return "\(machine)/\(name)"
    }

    /// The store's own four, taking the key itself. A screen that already holds a key — the
    /// hidden list in Settings is a list of them — asks with it rather than inventing a session
    /// to ask with.
    public func isFavorite(_ key: String) -> Bool { favorites.contains(key) }
    public func isHidden(_ key: String) -> Bool { hidden.contains(key) }

    public mutating func toggleFavorite(_ key: String) {
        favorites.formSymmetricDifference([key])
    }

    /// The same four asked about a session, which is how every screen but that one asks.
    public func isFavorite(_ session: Session) -> Bool { isFavorite(Self.key(session)) }
    public func isHidden(_ session: Session) -> Bool { isHidden(Self.key(session)) }

    public mutating func toggleFavorite(_ session: Session) {
        toggleFavorite(Self.key(session))
    }

    public mutating func setHidden(_ session: Session, _ hide: Bool) {
        setHidden(Self.key(session), hide)
    }

    /// Carry what you decided about a session onto its new name, on its own machine.
    ///
    /// These are keyed by name because a session that restarts keeps its name and gets a new
    /// id — which is the right trade until the name itself changes, and then the star has to
    /// be moved by hand or it is silently lost.
    public mutating func renamed(from old: String, to new: String, on machine: String? = nil) {
        let was = Self.key(machine, old)
        let now = Self.key(machine, new)
        if favorites.remove(was) != nil { favorites.insert(now) }
        if hidden.remove(was) != nil { hidden.insert(now) }
    }

    public mutating func setHidden(_ key: String, _ hide: Bool) {
        if hide {
            hidden.insert(key)
            favorites.remove(key)
        } else {
            hidden.remove(key)
        }
    }

    /// The same preferences with every bare name filed under the machine it was always about.
    ///
    /// A star written before the network was written on a phone paired to one Mac, so that Mac
    /// is where it belongs — which is why this takes the primary machine's id rather than
    /// guessing from whatever sessions happen to be on screen. Nothing to do once every key has
    /// a machine on it, so it is safe to run on every listing and it returns `self` unchanged.
    public func migrated(onto primary: String) -> Preferences {
        guard !primary.isEmpty else { return self }
        var moved = self
        moved.favorites = Self.prefixed(favorites, primary)
        moved.hidden = Self.prefixed(hidden, primary)
        return moved
    }

    /// The session half of a key, for a screen listing them: `m2/deckhand` reads `deckhand`.
    public static func name(of key: String) -> String {
        key.split(separator: "/", maxSplits: 1).last.map(String.init) ?? key
    }

    private static func prefixed(_ names: Set<String>, _ primary: String) -> Set<String> {
        Set(names.map { $0.contains("/") ? $0 : "\(primary)/\($0)" })
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
