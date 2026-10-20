import Foundation

/// What the addresses page and its square say, and which URL a tap opens. Pure, so `just test`
/// holds it down. The order and the tiers are the Mac's (`addresses/ranking.py`); this only
/// words them.
public enum Addresses {
    /// The Mac's three tiers, each in the order it sent them: newest first.
    public struct Tiers: Sendable {
        public let important: [Address]
        public let recent: [Address]
        public let rest: [Address]
        public var isEmpty: Bool { important.isEmpty && recent.isEmpty && rest.isEmpty }
    }

    public static func tiers(_ rows: [Address]) -> Tiers {
        Tiers(important: rows.filter { $0.tier == "important" }, recent: rows.filter { $0.tier == "recent" },
              rest: rows.filter { $0.tier != "important" && $0.tier != "recent" })
    }

    /// The address as a person says it: no scheme, no `www.`.
    public static func label(_ address: Address) -> String {
        let bare = address.origin.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return bare.hasPrefix("www.") ? String(bare.dropFirst(4)) : bare
    }

    /// What a row is called: the page's own title where it has one, else the address.
    public static func name(_ address: Address) -> String {
        address.title.isEmpty ? label(address) : address.title
    }

    /// Only what is wrong is said. A working address says nothing beside its dot, so the eye
    /// stops on the rows that need it.
    public static func problem(_ address: Address) -> String? {
        switch address.state {
        case "locked": address.note.isEmpty ? "Needs a password" : address.note.capitalizedFirst
        case "fails": address.status > 0 ? "Error \(address.status)" : "Error"
        case "down": address.note.isEmpty ? "Not answering" : address.note.capitalizedFirst
        default: nil
        }
    }

    /// The reason it is here and how long ago it was named: "Staging · 12 min ago".
    public static func why(_ address: Address, now: Date = .now) -> String {
        let ago = date(address.lastAt).map { stamp in
            let words = RelativeDateTimeFormatter()
            words.unitsStyle = .abbreviated
            return words.localizedString(for: stamp, relativeTo: now)
        }
        return [address.why, ago ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Claude Code writes `2026-10-20T10:00:00.123Z`; the plain parser refuses the fraction.
    static func date(_ stamp: String) -> Date? {
        let parse = ISO8601DateFormatter()
        parse.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parse.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp)
    }

    /// The URL a tap opens: the one that works from the phone, when the Mac found one.
    ///
    /// A loopback address is true only on the Mac. Where it also answers on the Mac's LAN
    /// address that is the one; where atlas gives it a dev hostname, that; and only then the
    /// address as written, which the session view's `LocalLinks` still offers to move.
    public static func opens(_ address: Address) -> URL? {
        if !address.lanUrl.isEmpty { return URL(string: address.lanUrl) }
        let path = address.paths.first ?? ""
        if address.reach == "mac", let local = address.atlas?.local, !local.isEmpty {
            return URL(string: local + path)
        }
        return URL(string: address.origin + path)
    }

    /// Every URL this address could sensibly be opened as, the best first and each once.
    public static func choices(_ address: Address) -> [URL] {
        let atlas = [address.atlas?.local, address.atlas?.remote].compactMap { $0 }.filter { !$0.isEmpty }
        let paths = address.paths.isEmpty ? [""] : address.paths
        let candidates = [opens(address)] + paths.map { URL(string: address.origin + $0) }
            + atlas.map { URL(string: $0) }
        var seen = Set<URL>()
        return candidates.compactMap { $0 }.filter { seen.insert($0).inserted }
    }

    /// The square's number: how many matter, else how many were found.
    public static func count(_ rows: [Address]?) -> String {
        guard let rows else { return "…" }
        if rows.isEmpty { return "None yet" }
        let important = tiers(rows).important.count
        return important > 0 ? "\(important) to look at" : "\(rows.count) found"
    }

    /// The three under the number, in the Mac's order — which is already most important first.
    public static func worth(_ rows: [Address]) -> [String] {
        Dashboard.few(rows).map(label)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
