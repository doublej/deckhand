import Foundation

/// Everything this Mac changes about what was said, in the order it happens, and where each
/// rule came from.
///
/// Four things stand between a mouth and a session, and only two of them are lists somebody
/// wrote down:
///
/// 1. **Hints.** Before the clip is even recorded, utt is handed the words to expect —
///    Deckhand's own jargon, *the right-hand side of every alias*, the session's name and its
///    folder (`transcribe.hints_for`). This is a bias and not a replacement, and it is the one
///    that catches people out: a word can come back as something else with no rule on this
///    screen having fired, because a hint made the recogniser prefer it.
/// 2. **utt's own pipeline** — its replacements, cleanup and formatting. Not reachable from
///    here in either direction; `settings/aliases.py` writes out why. Named on the screen so
///    that a swap belonging to none of the lists below has somewhere to have come from.
/// 3. **This Mac's aliases**, in list order, the moment utt answers — before any chain, and
///    before the manager. Every session alike.
/// 4. **This session's chain**, steps in their saved order. A step with a `pairs` field is a
///    second word list, belonging to this one terminal; anything else changes the words in its
///    own way and only the Mac can say how.
///
/// 3 and 4 run in that order and nothing merges them: a word matched by both is swapped twice,
/// the second on the first's output. That cascade is why ``Follow`` exists — a list of pairs
/// read top to bottom does not tell you what a sentence actually comes out as.
public enum Replacements {
    /// Where a rule comes from. The whole point of the screen: a flat list that does not say
    /// why a rule is in force is a list you cannot act on.
    public enum Source: Hashable, Sendable {
        /// The Mac-wide list. Every session, and the manager.
        case aliases
        /// One step of this session's chain, at its place in the saved order.
        case filter(place: Int, name: String)

        /// Where this rule lives, said in one phrase.
        public var label: String {
            switch self {
            case .aliases: "this Mac's aliases"
            case .filter(_, let name): "the \(name) step of this session's chain"
            }
        }
    }

    /// What something further down does to a rule's words. Computed over every rule in force,
    /// across both scopes, because the two scopes are where a collision actually comes from.
    public enum Follow: Hashable, Sendable {
        /// These words are swapped again below, and come out as this.
        case chained(into: String)
        /// Something above already changes the words this rule is looking for, so it may never
        /// see them. "May", not "does": an overlap is not always total.
        case shadowed(behind: String)

        public var label: String {
            switch self {
            case .chained(let into): "swapped again below — ends as \"\(into)\""
            case .shadowed(let word): "may never fire — \"\(word)\" is changed above it"
            }
        }
    }

    /// One replacement: what it matches, what it becomes, and where it came from.
    public struct Rule: Identifiable, Hashable, Sendable {
        public let heard: String
        public let meant: String
        public let source: Source
        /// Where this sits in the whole run, 1-based across every scope. Identity as well as
        /// order: the same pair may legitimately be written in two scopes at once.
        public let order: Int
        public let follow: Follow?

        public var id: Int { order }

        /// The row said out loud, for anyone who is not looking at it. An arrow between two
        /// monospaced words reads as nothing at all.
        public var label: String {
            let meantWords = meant.isEmpty ? "nothing" : "\"\(meant)\""
            var said = "\"\(heard)\" becomes \(meantWords), from \(source.label)"
            if let follow { said += ", \(follow.label)" }
            return said
        }
    }

    /// A scope either keeps a list of pairs or it does not, and the two are different things on
    /// screen rather than one thing with an empty list.
    public enum Doing: Hashable, Sendable {
        /// Rows of two, which is the whole of what this step does.
        case swaps([Rule])
        /// It changes the words in some other way, and only the Mac can say how — so this
        /// carries the Mac's own sentence rather than anything this phone made up.
        case otherwise(String)
    }

    /// One scope, with everything it does.
    public struct Stage: Identifiable, Hashable, Sendable {
        public let source: Source
        public let title: String
        /// What it covers: every session, or this terminal only.
        public let detail: String
        public let doing: Doing

        public var id: Source { source }

        public var rules: [Rule] {
            if case .swaps(let rules) = doing { return rules }
            return []
        }
    }

    /// Every scope in force for one session, in run order.
    ///
    /// The aliases stage is always here, empty list or not: it is the one scope that can be
    /// edited from this screen, and a group that vanishes when it is empty is a group nobody
    /// finds. Chain steps appear only while they are switched on — this answers what is running
    /// now, not what could be.
    public static func inForce(aliases: [Alias], chain: [FilterStep], known: [Filter]) -> [Stage] {
        var stages = [Stage(source: .aliases,
                            title: "This Mac's aliases",
                            detail: "Every session, and the manager. Swapped the moment utt "
                            + "answers, before any of the steps below.",
                            doing: .swaps(rows(aliases, from: .aliases)))]
        for (place, step) in chain.enumerated() where step.isOn {
            stages.append(stage(step, place: place, known: known))
        }
        return numbered(stages)
    }

    /// The words utt is told to expect, as far as this phone can know them.
    ///
    /// Deliberately not the whole list: `transcribe.VOCABULARY` is a fixed set of this
    /// project's own jargon that only changes with a release of the Mac, and there is no route
    /// that hands it over. The two halves below are the ones that move — and the alias half is
    /// the one that can surprise somebody, because a word they once corrected *to* is from then
    /// on a word the recogniser leans towards everywhere.
    public struct Hints: Hashable, Sendable {
        /// The right-hand side of every alias.
        public let fromAliases: [String]
        /// The session's own name and the last of its folder.
        public let fromSession: [String]

        public var isEmpty: Bool { fromAliases.isEmpty && fromSession.isEmpty }
    }

    /// Mirrors `transcribe.hints_for`: the name split on hyphens, the last two parts of the
    /// folder, every alias's meant side, sorted, and nothing shorter than three letters.
    public static func hints(aliases: [Alias], name: String, cwd: String) -> Hints {
        let folder = cwd.split(separator: "/").suffix(2).map(String.init)
        return Hints(
            fromAliases: kept(aliases.compactMap { $0.count == 2 ? $0[1] : nil }),
            fromSession: kept(name.replacingOccurrences(of: "-", with: " ").split(
                separator: " ").map(String.init) + folder.filter { $0 != "Users" })
        )
    }

    private static func kept(_ words: [String]) -> [String] {
        Set(words.filter { $0.count > 2 }).sorted()
    }

    /// One chain step as a scope. A step naming a filter this Mac no longer offers keeps its
    /// place and says so, the same answer `SessionFilters` gives: a step quietly left out of
    /// this list is a rule running with nothing on screen to account for it.
    private static func stage(_ step: FilterStep, place: Int, known: [Filter]) -> Stage {
        let source = Source.filter(place: place, name: step.filter)
        guard let filter = known.first(where: { $0.name == step.filter }) else {
            return Stage(source: source, title: step.filter,
                         detail: "This session only.",
                         doing: .otherwise("This Mac no longer offers this filter."))
        }
        let detail = "This session only. Another session has its own chain."
        let pairs = filter.fields.filter { $0.kind == .pairs }
        guard !pairs.isEmpty else {
            return Stage(source: source, title: filter.title, detail: detail,
                         doing: .otherwise(filter.summary))
        }
        let rows = pairs.flatMap { (step.settings[$0.key] ?? $0.defaultValue).rows }
        return Stage(source: source, title: filter.title, detail: detail,
                     doing: .swaps(self.rows(rows, from: source)))
    }

    /// Rows of two as rules, dropping the ones the Mac itself skips: a pair with nothing on its
    /// left is not an instruction to rewrite every gap in the sentence. Same rule as
    /// `aliases._pairs`, and the reason a blank row being typed does not appear here as one.
    private static func rows(_ pairs: [[String]], from source: Source) -> [Rule] {
        pairs.compactMap { pair in
            guard pair.count == 2 else { return nil }
            let heard = pair[0].trimmingCharacters(in: .whitespaces)
            guard !heard.isEmpty else { return nil }
            return Rule(heard: heard, meant: pair[1].trimmingCharacters(in: .whitespaces),
                        source: source, order: 0, follow: nil)
        }
    }

    /// The run order over every scope at once, and what each rule's words meet further down.
    ///
    /// One pass over a flat list, because that is what actually runs: the chain does not see a
    /// list of scopes, it sees a sentence that the scope above already changed.
    private static func numbered(_ stages: [Stage]) -> [Stage] {
        var flat: [Rule] = []
        for stage in stages {
            for rule in stage.rules {
                flat.append(Rule(heard: rule.heard, meant: rule.meant, source: rule.source,
                                 order: flat.count + 1, follow: nil))
            }
        }
        let followed = flat.map { rule in
            Rule(heard: rule.heard, meant: rule.meant, source: rule.source,
                 order: rule.order, follow: follow(rule, among: flat))
        }
        var spot = 0
        return stages.map { stage in
            guard case .swaps(let rules) = stage.doing else { return stage }
            let mine = Array(followed[spot..<(spot + rules.count)])
            spot += rules.count
            return Stage(source: stage.source, title: stage.title, detail: stage.detail,
                         doing: .swaps(mine))
        }
    }

    /// Shadowed before chained: a rule that never fires is the stronger fact about it, and
    /// saying what its output becomes would be describing something that does not happen.
    private static func follow(_ rule: Rule, among flat: [Rule]) -> Follow? {
        let above = flat.prefix(rule.order - 1)
        if let blocker = above.first(where: { AliasText.matches($0.heard, in: rule.heard) }) {
            return .shadowed(behind: blocker.heard)
        }
        let below = flat.dropFirst(rule.order)
        let ended = below.reduce(rule.meant) { text, next in
            AliasText.swapped(text, heard: next.heard, meant: next.meant)
        }
        return ended == rule.meant ? nil : .chained(into: ended)
    }
}
