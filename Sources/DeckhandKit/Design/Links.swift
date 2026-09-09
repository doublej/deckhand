import Foundation
import SwiftUI

/// What a session writes down that you might want to open, and what it means from a phone.
///
/// Sessions write addresses constantly — a dev server it just started, a PR it opened, a page it
/// wants looked at — and on a phone every one of them was dead text you would have to retype.
/// The tricky half is `localhost`: true where the session is running, and on the phone it means
/// the phone, which is running none of the things the session is talking about.
public enum Links {
    /// Hosts that mean "the machine this was written on", which is never the phone.
    static let local: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]"]

    /// Plain text with every address in it marked, so a `Text` renders them as taps.
    public static func marked(_ text: String) -> AttributedString {
        linked(AttributedString(text))
    }

    /// The same, over text that already carries styling — the summary, which is markdown first.
    ///
    /// `NSDataDetector` rather than a pattern of my own: it is what the rest of the system uses
    /// to find an address in a message, so what is tappable here is what is tappable everywhere
    /// else. Anything markdown already linked is left exactly as it is.
    public static func linked(_ attributed: AttributedString) -> AttributedString {
        var out = attributed
        let plain = String(attributed.characters)
        guard !plain.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return out }
        for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
            guard let url = match.url, let span = range(of: match.range, in: out, plain: plain),
                  out[span].link == nil else { continue }
            out[span].link = url
            out[span].underlineStyle = .single
            out[span].foregroundColor = Palette.tint
        }
        return out
    }

    /// The detector counts UTF-16; an `AttributedString` counts characters. Going through the
    /// plain string's own indices is what keeps an emoji earlier in the line from shifting them.
    private static func range(
        of found: NSRange, in attributed: AttributedString, plain: String
    ) -> Range<AttributedString.Index>? {
        guard let span = Range(found, in: plain) else { return nil }
        let from = plain.distance(from: plain.startIndex, to: span.lowerBound)
        let count = plain.distance(from: span.lowerBound, to: span.upperBound)
        let start = attributed.index(attributed.startIndex, offsetByCharacters: from)
        return start..<attributed.index(start, offsetByCharacters: count)
    }

    /// True for an address that names the machine it was written on.
    public static func isLocal(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return local.contains(host) || host.hasSuffix(".localhost")
    }

    /// The same address on every machine it could sensibly mean, the original first.
    ///
    /// Two candidates for the Mac, and they are not interchangeable: the address this phone is
    /// already reaching it on is proven to work, and the one the Mac reports for itself is the
    /// one that still works when a `.local` name will not resolve. Both are offered rather than
    /// guessed between — which is the whole point of a link that cannot be taken at its word.
    public static func choices(for url: URL, mac: String?, paired: String) -> [URL] {
        var seen = Set([url.absoluteString])
        var out = [url]
        for candidate in [mac, hostOnly(paired)] {
            guard let host = candidate, !host.isEmpty, !local.contains(host.lowercased()),
                  var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { continue }
            parts.host = host
            guard let moved = parts.url, seen.insert(moved.absoluteString).inserted else { continue }
            out.append(moved)
        }
        return out
    }

    /// The settings field holds whatever was typed: a bare name, a name and a port, or a URL.
    private static func hostOnly(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .whitespaces)
        if let parsed = URLComponents(string: trimmed)?.host, !parsed.isEmpty { return parsed }
        return trimmed.split(separator: ":").first.map(String.init) ?? trimmed
    }
}
