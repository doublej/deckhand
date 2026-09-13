import Foundation

/// A list of aliases as somebody is typing into it, rather than as the Mac is running it.
///
/// `PUT /aliases` answers with what was **stored**, and that contract is right — the daemon is
/// the one that decides what its list is. But both screens that draw the list write it on the
/// way *off* the page, so the answer arrives after the view is gone and there is nothing left
/// to show it on. A row the Mac declined is then simply absent the next time the list is
/// opened, with nothing connecting the absence to the typing that caused it.
///
/// So the rules are mirrored here and applied live: the screen says which row will not survive
/// while it is still on screen and still editable. Nothing round-trips, because nothing needs
/// to — `aliases._kept` is deterministic and its two typed-into rules are small.
public extension Replacements {

    /// A row this Mac will not keep, named so it can be found, with the reason it goes.
    ///
    /// Worked out before the save rather than discovered after it, and that is the whole point.
    /// `PUT /aliases` answers with what was *stored*, which is right — but the screen writes on
    /// the way out, so the answer lands after it is gone and the row is simply missing the next
    /// time the list is opened. Told here, while the row is still on screen and still typed into,
    /// it is a correction somebody can make instead of a disappearance they have to explain.
    struct Dropped: Identifiable, Hashable, Sendable {
        /// Which row, as an index into the list being edited.
        public let row: Int
        public let why: String

        public var id: Int { row }
    }

    /// The rows `aliases.save` would throw away, in the order they sit in.
    ///
    /// Mirrors the two rules a person reaches by typing — nothing on the left, and the same word
    /// aliased twice — and deliberately not the third. A row that is not two elements is dropped
    /// too, but nothing in this app can build one: `Alias` is `[String]` and `Pairs` only ever
    /// appends a pair, so warning about it would be warning about a broken client rather than
    /// about anything the person in front of the list can do.
    ///
    /// A row with nothing typed into it at all is not a mistake and says nothing. It is what
    /// "Add a replacement" just made, and calling it an error the moment it appears would put a
    /// warning under every new row before anybody had a chance to fill it in.
    static func dropped(_ aliases: [Alias]) -> [Dropped] {
        // ponytail: `lowercased()` where the Mac casefolds. They part only on the likes of "ß"
        // against "ss", which no dictation word list here has ever held; swap in a real
        // case-folding if one ever does.
        var last: [String: Int] = [:]
        for (row, pair) in aliases.enumerated() {
            let heard = side(pair, 0)
            if !heard.isEmpty { last[heard.lowercased()] = row }
        }
        return aliases.enumerated().compactMap { row, pair in
            let heard = side(pair, 0), meant = side(pair, 1)
            guard !heard.isEmpty else {
                guard !meant.isEmpty else { return nil }
                return Dropped(row: row, why: "the row meaning \"\(meant)\" has nothing on its "
                               + "left to match, so this Mac will not keep it")
            }
            guard last[heard.lowercased()] != row else { return nil }
            return Dropped(row: row, why: "\"\(heard)\" is aliased again below, and the later "
                           + "answer wins — this row's own answer will not be used")
        }
    }

}

/// The two rules themselves, shared with ``Replacements/inForce(aliases:chain:known:)``
/// so that what is listed as in force and what is warned about as dropped cannot disagree.
extension Replacements {
    static func side(_ pair: Alias, _ half: Int) -> String {
        pair.count == 2 ? pair[half].trimmingCharacters(in: .whitespaces) : ""
    }

    /// The Mac's own reading of its list: one row per word, keyed on the heard side with case
    /// ignored, the later answer winning and keeping the earlier one's place. `aliases._kept`,
    /// mirrored — and mirrored here rather than left out because the list being *edited* can
    /// hold a word twice for as long as somebody is retyping an answer, while the list the Mac
    /// runs never can.
    ///
    /// Listing both would put a rule on screen that cannot exist, and `follow` would then mark
    /// the surviving answer as shadowed by the very row being thrown away — the truth inverted,
    /// on the one screen whose whole job is saying what is really in force. Only this list is
    /// keyed by word: a filter's `pairs` keeps both rows and fires both, so `rows(_:from:)`
    /// leaves the chain alone.
    static func keptAliases(_ aliases: [Alias]) -> [Alias] {
        var kept: [Alias] = []
        var place: [String: Int] = [:]
        for pair in aliases where !side(pair, 0).isEmpty {
            let word = side(pair, 0).lowercased()
            if let already = place[word] {
                kept[already] = pair
            } else {
                place[word] = kept.count
                kept.append(pair)
            }
        }
        return kept
    }

}
