import Foundation

/// What the addresses page and its square say, and which URL a tap opens. Pure, so `just test`
/// holds it down.
public enum Addresses {
    /// Where an address can be opened from, in the order the page reads them: what is running
    /// here first, then the rest of the house, then the internet, then what never resolved.
    public static let reaches: [(key: String, title: String)] = [
        ("mac", "Only on the Mac"), ("home", "Home network"), ("public", "Internet"),
        ("none", "Does not resolve"), ("", "Checking")
    ]

    /// The rows under each heading that has any, in the order the Mac sent them.
    public static func sections(_ rows: [Address]) -> [(title: String, rows: [Address])] {
        reaches.compactMap { reach in
            let found = rows.filter { $0.reach == reach.key }
            return found.isEmpty ? nil : (reach.title, found)
        }
    }

    /// The address as a person says it: no scheme, no `www.`.
    public static func label(_ address: Address) -> String {
        let bare = address.origin.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return bare.hasPrefix("www.") ? String(bare.dropFirst(4)) : bare
    }

    /// What the check found, in two words.
    public static func verdict(_ address: Address) -> String {
        switch address.state {
        case "loads": "Loads"
        case "locked": "Locked"
        case "fails": address.status > 0 ? "Error \(address.status)" : "Error"
        case "down": "Not answering"
        default: "Checking…"
        }
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

    /// The square's number: how many answer, else how many were found.
    public static func count(_ rows: [Address]?) -> String {
        guard let rows else { return "…" }
        if rows.isEmpty { return "None yet" }
        let live = rows.filter(\.answers).count
        return live > 0 ? "\(live) live" : "\(rows.count) found"
    }

    /// The three under the number: ones that answer first, chosen ones before printed ones.
    public static func worth(_ rows: [Address]) -> [String] {
        Dashboard.few(rows.filter(\.answers) + rows.filter { !$0.answers }).map(label)
    }
}
