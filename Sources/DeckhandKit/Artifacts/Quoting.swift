import Foundation

// What a session is told about a passage the person picked out of a slip and then talked about.
// Here rather than in the view for the reason `Underneath` is here: there is nothing visual about
// it, and it is the one place in commenting where the words a session acts on are decided.

/// A passage out of a slip, and what was said about it.
public enum Quote {
    /// How much of a selection travels, in characters.
    ///
    /// A selection is whatever a finger dragged over, and a finger can drag over a whole document:
    /// `select all` on a long page is tens of thousands of characters, and every one of them would
    /// go into the review card and then be *typed* into an iTerm pane by the keyboard route. So
    /// there is a ceiling, it is generous enough that no ordinary paragraph meets it, and when it
    /// is met the prose says so — a quote silently missing its end is the one outcome worth more
    /// than the code that prevents it.
    public static let longest = 1500

    /// What goes on the review card: where the passage came from, the passage, then what was said.
    ///
    /// In that order, because it is the order the person did it in — they picked the passage first
    /// and talked about it second — and because a session reading the card needs to know what is
    /// being talked about before it reads the remark.
    ///
    /// The slip is named by its title and its slug. The title is what the person saw and the slug
    /// is the file's own name, so between them a session can find the thing without being handed a
    /// path this phone cannot honestly claim to know. Nothing here invents a line number: a
    /// selection is characters on a rendered page, not a place in a file.
    ///
    /// Either half may be missing and the prose stays true. A selection that was gone by the time
    /// it was read is not quoted and not pretended at — the remark says it is *about* the slip
    /// instead. Nothing said about a passage is the passage alone, which is what a caller that
    /// heard nothing should be laying down rather than this.
    public static func prose(_ said: String,
                             about passage: String,
                             from title: String,
                             id: String) -> String {
        let remark = said.trimmingCharacters(in: .whitespacesAndNewlines)
        let (quoted, cut) = kept(passage)
        let parts = quoted.isEmpty
            ? ["About \(named(title, id)):"]
            : ["From \(named(title, id)):", "", quoted] + (cut ? ["", ceiling] : [])
        return (remark.isEmpty ? parts : parts + ["", remark]).joined(separator: "\n")
    }

    /// `"What the footer should say" (`footer`)`, or the slug alone where a slip has no title.
    ///
    /// The slug is fenced in backticks for the reason `Pin.prose` fences a path: it is a name a
    /// session will type, and the punctuation around it must not be readable as part of it.
    private static func named(_ title: String, _ id: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "`\(id)`" : "\"\(name)\" (`\(id)`)"
    }

    /// The passage as a markdown blockquote, and whether it had to be cut short.
    ///
    /// As it was, line for line: a selection is characters the person chose, so the blank lines and
    /// the indentation inside it are theirs. Only the ends are trimmed, and `\r\n` is folded to
    /// `\n` so a quote out of a page written on Windows does not arrive with a stray mark on every
    /// line.
    private static func kept(_ passage: String) -> (quote: String, shortened: Bool) {
        let whole = passage.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !whole.isEmpty else { return ("", false) }
        let cut = whole.count > longest
        let text = cut ? trimmed(whole) + "…" : whole
        let lines = text.components(separatedBy: "\n").map { $0.isEmpty ? ">" : "> \($0)" }
        return (lines.joined(separator: "\n"), cut)
    }

    /// The first `longest` characters, ending on a word where there is one to end on. A quote that
    /// stops mid-word reads as a typo rather than as a cut.
    private static func trimmed(_ whole: String) -> String {
        let head = String(whole.prefix(longest))
        guard let gap = head.lastIndex(where: \.isWhitespace),
              head.distance(from: head.startIndex, to: gap) > longest / 2 else { return head }
        return String(head[..<gap])
    }

    /// The one line that makes a shortened quote honest, naming the ceiling rather than hinting at
    /// it: a session that can see how much is missing can ask for the rest, or go and read the file.
    private static let ceiling =
        "(The selection ran on past this — these are its first \(longest) characters.)"
}
