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
    public static func marked(_ text: String, in tint: Color = Palette.tint) -> AttributedString {
        linked(AttributedString(text), in: tint)
    }

    /// The same, over text that already carries styling — the summary, which is markdown first.
    ///
    /// `NSDataDetector` rather than a pattern of my own: it is what the rest of the system uses
    /// to find an address in a message, so what is tappable here is what is tappable everywhere
    /// else. Anything markdown already linked is left exactly as it is.
    ///
    /// `tint` is the colour an address is drawn in, and it is a parameter rather than a read of
    /// `\.accent` because this is not a view: an `AttributedString` is built outside the view tree
    /// and has no environment to read. A caller that is a view passes what it read there; the
    /// default is for the ones with no opinion.
    public static func linked(_ attributed: AttributedString, in tint: Color = Palette.tint) -> AttributedString {
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
            out[span].foregroundColor = tint
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

// MARK: - the pointer over a link, on the Mac

public extension Links {
    /// `attributed` as a `Text` — and on the Mac, a pointing hand over its links.
    ///
    /// A link inside a `Text` is a run of characters, not a view, so AppKit never gets a cursor
    /// rect for it: the pointer stays an arrow, or the I-beam on selectable text, right over
    /// something that opens when clicked. So the link runs are marked as the text is built, the
    /// renderer notes where it drew them, and hovering one of those rects asks for `.link`.
    @ViewBuilder static func text(_ attributed: AttributedString) -> some View {
        #if os(macOS)
        Text(marking: attributed).modifier(LinkPointer())
        #else
        Text(attributed)
        #endif
    }
}

#if os(macOS)
/// A run of a `Text` that is a link.
private struct LinkRun: TextAttribute {}

private extension Text {
    init(marking attributed: AttributedString) {
        self = attributed.runs.reduce(Text(verbatim: "")) { text, run in
            let piece = Text(AttributedString(attributed[run.range]))
            return text + (run.link == nil ? piece : piece.customAttribute(LinkRun()))
        }
    }
}

/// Where the links were last drawn. A class, because the renderer writes it while drawing and
/// nothing should redraw because it changed.
private final class LinkRects: @unchecked Sendable {
    var rects: [CGRect] = []
}

private struct LinkRenderer: TextRenderer {
    let drawn: LinkRects

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var rects: [CGRect] = []
        for line in layout {
            for run in line {
                if run[LinkRun.self] != nil { rects.append(run.typographicBounds.rect) }
                context.draw(run)
            }
        }
        drawn.rects = rects
    }
}

private struct LinkPointer: ViewModifier {
    @State private var drawn = LinkRects()
    @State private var over = false

    func body(content: Content) -> some View {
        content
            .textRenderer(LinkRenderer(drawn: drawn))
            .onContinuousHover { phase in
                guard case .active(let spot) = phase else { return over = false }
                over = drawn.rects.contains { $0.contains(spot) }
            }
            .pointerStyle(over ? .link : nil)
    }
}
#endif
