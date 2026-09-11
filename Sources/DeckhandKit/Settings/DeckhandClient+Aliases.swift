import Foundation

/// What was heard, and what was meant — the Mac-wide list, and picking one out of a sentence.
///
/// An **alias** is one pair: the words utt hands back, and the words that were actually said.
/// It is global to the Mac rather than per terminal or per folder, because a word comes back
/// wrong because of a voice and a model — which no folder has an opinion about. The per-terminal
/// list is the `words` filter and is still there for a word that only means something in one
/// project; `daemon/src/deckhand_daemon/settings/aliases.py` says why they are two things.
///
/// Carried as rows of two on the wire, the same shape the `words` filter's `pairs` field takes,
/// so one editor (``Pairs``) can draw either of them.
public typealias Alias = [String]

public extension DeckhandClient {
    /// Every alias this Mac swaps on the way out of utt.
    func aliases() async throws -> [Alias] {
        try literal(try await send(request(.get, "aliases"))).aliases
    }

    /// Replace the list whole, and take the Mac's own reading of it back — what it stores is not
    /// always what was sent: a row with nothing on its left is dropped, and a word aliased twice
    /// keeps only the later answer. A screen following its own copy would be showing a list the
    /// Mac is not running.
    @discardableResult
    func saveAliases(_ aliases: [Alias]) async throws -> [Alias] {
        var req = request(.put, "aliases")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(AliasList(aliases: aliases))
        return try literal(try await send(req, body: body)).aliases
    }

    /// One decoder with no key strategy, the same one `settings()` and `filters()` use and for
    /// the same written-down reason: an alias is somebody's words, and a converter that rewrites
    /// them is a list quietly saying something else.
    private func literal(_ data: Data) throws -> AliasList {
        try JSONDecoder().decode(AliasList.self, from: data)
    }
}

/// What both calls carry. Tolerant on the way in like everything else off this wire — a Mac and
/// a phone are routinely a version apart, and a missing key is an empty list, never a throw.
struct AliasList: Codable {
    var aliases: [Alias] = []

    init(aliases: [Alias]) {
        self.aliases = aliases
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        aliases = try box.decodeIfPresent([Alias].self, forKey: .aliases) ?? []
    }
}

/// The words of a transcript, one at a time, and the alias a run of them makes.
///
/// Here rather than in the view for the usual reason: everything in this module is reachable by
/// `just test`, and which characters end up on the left-hand side of somebody's permanent word
/// list is exactly the kind of thing that should be held down by a test rather than by a
/// screenshot.
public enum AliasText {
    /// The sentence split for tapping: every run of non-space characters, in order.
    ///
    /// Whitespace and nothing else, so a word keeps whatever is stuck to it — "deckhand," stays
    /// one word. Splitting on punctuation too would put a comma on screen as its own tappable
    /// chip, which is a thing nobody wants to tap.
    public static func words(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// What a run of tapped words means as an alias's left-hand side.
    ///
    /// Joined with one space, and trimmed of punctuation at the two ends only. The match on the
    /// Mac is word-bounded, so "deckhand," would match — and would then be an alias that fires
    /// only where the word happens to end a clause, which is how a word list fills up with
    /// near-duplicates nobody can read. Punctuation *inside* the run is kept: "don't" is a word.
    ///
    /// `.punctuationCharacters` rather than everything non-alphanumeric, and the difference is
    /// load-bearing: Unicode files `+` as a symbol rather than punctuation, so "c++" survives
    /// this and "deckhand," does not. Which is the answer both of them want.
    ///
    /// Empty when there is nothing left after the trim, which is what tapping a bare "—" gives.
    public static func heard(_ words: [String]) -> String {
        words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
    }

    /// The one alias just written, applied to the words already on the card.
    ///
    /// The other half of the fix, and the reason it is here rather than left to the next clip:
    /// somebody aliasing a word is looking at that word being wrong. Saving the rule and leaving
    /// the mistake on screen would make them correct it twice.
    ///
    /// Deliberately the same rule as `aliases.swap` on the Mac — whole words, case ignored on
    /// the way in, taken as written on the way out — because the next clip goes through that one
    /// and two rules that disagree is a card that stops matching what gets sent. A pattern that
    /// will not compile leaves the words alone, which is the same answer as an alias that never
    /// fires.
    public static func swapped(_ text: String, heard: String, meant: String) -> String {
        let pattern = "(?<!\\w)\(NSRegularExpression.escapedPattern(for: heard))(?!\\w)"
        guard !heard.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: meant)
        )
    }
}
