import Foundation

/// One machine on the home network, as the Mac describes it.
///
/// The phone never learns that a machine is reached over ssh, or that anything runs on it: a
/// machine is a name, whether it can be talked to, and why not when it cannot. Everything about
/// how the Mac gets there is the Mac's.
public struct Machine: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    /// What the Mac calls it. Never rendered raw — see ``title``.
    public let label: String
    /// `darwin`, `linux`, `win32`. Claude Code's own spelling, which is what the Mac has.
    /// Spelled `system` here and `os` on the wire: two letters is below this project's floor
    /// for a name, and the wire is the Mac's to spell.
    public let system: String
    /// Whether the Mac can reach it right now. Not a guess and not a cache: it is the state of
    /// the connection the Mac already holds open, so it costs nothing to ask.
    public let reachable: Bool
    /// Why it cannot be reached, in the Mac's words. Empty when it can.
    public let error: String
    /// Whether this is the machine the daemon itself runs on. Optional because a Mac that
    /// predates it says nothing, and a listing that would not decode is worse than a flag that
    /// is nil — the same rule every optional on `Session` follows.
    public var primary: Bool?

    enum CodingKeys: String, CodingKey {
        case id, label, reachable, error, primary
        case system = "os"
    }

    public init(
        id: String, label: String, system: String, reachable: Bool, error: String,
        primary: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.system = system
        self.reachable = reachable
        self.error = error
        self.primary = primary
    }

    /// What a screen may draw.
    ///
    /// `label` is display copy the phone renders verbatim and nothing validates it: it is
    /// hand-edited in atlas's `hosts.json` and through its console's registry editor, and atlas
    /// has no use for a length or an emptiness check. So the check is here — blank falls back to
    /// the `id`, which is always there and always short, and anything long is cut rather than
    /// allowed to push a row's state word off the screen.
    public var title: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? id : trimmed
        return name.count <= Self.titleLimit
            ? name
            : String(name.prefix(Self.titleLimit - 1)) + "…"
    }

    static let titleLimit = 24

    public var isPrimary: Bool { primary ?? false }

    /// The four-letter vocabulary the rest of the app says a state in. A machine that cannot be
    /// reached is off rather than broken *unless* the Mac had something to say about why —
    /// asleep is the ordinary case here and it is not an error.
    public var state: RunState {
        if reachable { return .online }
        return error.isEmpty ? .off : .err
    }
}
