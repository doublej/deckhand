import Foundation

/// What each square on a session's dashboard says, and how many of them fit across a page.
///
/// Here rather than in the app target for the reason every pure thing in this module is: a tile's
/// whole claim is that the number on it is true, and `just test` can only hold that down on the
/// Mac. Nothing in this file knows what a tile looks like — the drawing is
/// `deckhand/Views/Dashboard/`, and the order the tiles come in is the order they are written
/// there, because a grid's reading order is a layout fact rather than a rule anything can check.
///
/// **Every one of these answers the empty case in words, never with a zero.** "0 files" reads as
/// a number that failed to arrive; "None yet" reads as a session that has not made one — and on a
/// dashboard whose entire job is to be believed at a glance, those are not the same sentence.
///
/// A square says two things: one number, and up to three lines of what that number is *of* —
/// which slips, which subagents, which files. The second half is the preview, and the rule it
/// follows is the rule the number follows: it names what is still waiting on somebody before it
/// names what is done, and where there is nothing true to name it is an empty array and the tile
/// is shorter for it. Nothing here pads a square out to a shape.
public enum Dashboard {
    /// How many squares fit across a page this wide.
    ///
    /// Two on a phone held upright, which is what leaves a tile wide enough for its number to be
    /// read at arm's length — the bar every other surface in this app is drawn to. Four on its
    /// side, where the screen is twice as wide and half as tall. Three is the step between, for
    /// a window that is neither.
    public static func columns(across width: CGFloat) -> Int {
        switch width {
        case ..<480: 2
        case ..<700: 3
        default: 4
        }
    }

    /// The slips this session has put on the phone, waiting ones first.
    ///
    /// A slip with no answer beside it is the session stopped and waiting on a person, so it is
    /// the half worth the square whenever there is one — the answered count is what the tile
    /// falls back to saying once nothing is outstanding.
    public static func slips(waiting: Int, answered: Int) -> String {
        if waiting > 0 { return "\(waiting) waiting" }
        if answered > 0 { return "\(answered) answered" }
        return "None yet"
    }

    /// The files it touched that you could open.
    public static func files(_ count: Int) -> String {
        count == 0 ? "None yet" : "\(count) \(count == 1 ? "file" : "files")"
    }

    /// The subagents, the ones still going first.
    ///
    /// Running is the question the square is asked — how many are working right now — so it wins
    /// whenever there is one, exactly as a waiting slip wins over an answered one. The finished
    /// count is what it falls back to rather than "None": a session that has just run six agents
    /// still has six conversations worth opening, and a square reading "None" over them would be
    /// lying about the one thing it exists to answer.
    public static func agents(running: Int, finished: Int) -> String {
        if running > 0 { return "\(running) running" }
        if finished > 0 { return "\(finished) finished" }
        return "None yet"
    }

    /// The first line of the standing orders, which is the headline of that square.
    ///
    /// The first *non-empty* line: orders are dictated as often as they are typed, and a
    /// paragraph that opens on a blank line would otherwise put an empty tile over a session
    /// running under orders — the one lie this tile must not tell.
    public static func orders(_ text: String) -> String {
        opening(text) ?? "None standing"
    }

    /// The standing orders after that opening line, which is what fills the square beneath it.
    ///
    /// Blank lines are dropped rather than drawn. A paragraph break spends one of the three
    /// lines a square has and shows nothing for it, and the preview is there to say what the
    /// orders actually are — the tile said only their first line before, which for a dictated
    /// paragraph is often the least useful sentence in it.
    public static func rest(of text: String) -> [String] {
        few(written(in: text).dropFirst())
    }

    /// The first line somebody actually wrote, or nil where nothing was. The join between a
    /// square's headline and its preview, so both agree on what counts as a line.
    public static func opening(_ text: String) -> String? {
        written(in: text).first
    }

    /// Three lines is what a square has room for under its number, and the cap is written once
    /// here rather than at the six call sites that need it.
    ///
    /// A fourth line would either shrink the type past reading distance or push the grid back to
    /// the height the preview was added to take out of it.
    public static func few<Item>(_ found: some Sequence<Item>) -> [Item] {
        Array(found.prefix(3))
    }

    /// The slips worth naming under the count: the ones still waiting on a person first, newest
    /// first within each half.
    ///
    /// The same precedence the count itself follows, and for the same reason — a slip with no
    /// answer beside it is the session stopped. An answered slip is a page nobody is blocked on,
    /// so it earns a line only once nothing is outstanding.
    public static func asking(_ found: [Artifact]) -> [String] {
        let newest = found.sorted { $0.modified > $1.modified }
        return few(newest.filter { !$0.answered } + newest.filter(\.answered)).map(\.title)
    }

    /// The subagents worth naming under the count: the ones still going first, newest first
    /// within each half. `Agent.title` is the session's own sentence about what it wanted, which
    /// is the only human-written line about an agent anywhere.
    public static func doing(_ found: [Agent]) -> [String] {
        let newest = found.sorted { $0.updatedAt > $1.updatedAt }
        return few(newest.filter(\.running) + newest.filter { !$0.running }).map(\.title)
    }

    /// The files worth naming under the count, most recently touched first.
    ///
    /// The name alone, because a square is not wide enough for a path and the pane behind it has
    /// the path — **except where the name is not an answer.** A session that touched three
    /// CLAUDE.md files drew "CLAUDE.md" three times, which says a session touched three files and
    /// nothing else at all; a repeated name takes the folder it sits in, which is the same choice
    /// `Doc.label` already makes for the context tree and for the same reason. Only the repeats,
    /// so one ordinary filename is never widened into a path to keep a rule tidy.
    public static func touched(_ found: [Asset]) -> [String] {
        let newest = few(found.sorted { $0.modified > $1.modified })
        var seen: [String: Int] = [:]
        for asset in newest { seen[asset.name, default: 0] += 1 }
        return newest.map { asset in
            guard seen[asset.name] ?? 0 > 1 else { return asset.name }
            let above = folder(of: asset.path)
            return above.isEmpty ? asset.name : "\(above)/\(asset.name)"
        }
    }

    /// The folder a path sits in, by name. Empty for a file with nothing above it.
    private static func folder(of path: String) -> String {
        let parts = path.split(separator: "/")
        return parts.count >= 2 ? String(parts[parts.count - 2]) : ""
    }

    /// The `just` recipes this folder's own justfile offers to run directly.
    public static func commands(_ count: Int) -> String {
        count == 0 ? "No justfile" : "\(count) \(count == 1 ? "recipe" : "recipes")"
    }

    /// The recipes worth naming under the count, in the order `just` itself gave them — the tile
    /// has no groups to sort by, so it shows the file's own order rather than inventing one.
    public static func commandNames(_ recipes: [Recipe]) -> [String] {
        few(recipes).map { "just \($0.name)" }
    }

    /// The chain's running steps, under the names the filters sheet gives them.
    ///
    /// A chain is stored by slug — `max_words`, `replacements` — and a square listing slugs is a
    /// square showing the wire rather than the setting. `Filter.title` is what every other screen
    /// names them by, and a step naming a filter this Mac no longer offers keeps its slug rather
    /// than disappearing, exactly as `FilterRow.chain` refuses to drop one.
    public static func running(_ steps: [FilterStep], over known: [Filter]) -> [String] {
        let titles = Dictionary(known.map { ($0.name, $0.title) }) { first, _ in first }
        return steps.filter(\.isOn).map { titles[$0.filter] ?? $0.filter }
    }

    /// Every line somebody wrote, trimmed, with the blanks taken out.
    private static func written(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Everything being done to words on their way into this session, counted over every scope.
    ///
    /// **It counts the whole cascade and not the chain, and that is the whole point of it.** The
    /// square used to say "3 of 6 running" off the filter chain alone, which meant somebody with
    /// twelve aliases rewriting every clip and an empty chain read "Nothing running" and believed
    /// it. That is the misreading `Replacements` was built to end — JJ's "we" arriving at a
    /// session as "web" while every surface on the phone said nothing was touching his words.
    ///
    /// Swaps and rewrites are counted apart because they are different kinds of fact. A swap is a
    /// row of two, a word for a word. A rewrite is a scope that hands the whole sentence to a
    /// model and takes back another sentence, which cannot be added to a row count without the
    /// number meaning nothing.
    public static func swapping(_ counted: Replacements.Tally) -> String {
        if counted.isEmpty { return "Nothing changed" }
        let swaps = counted.swaps > 0 ? plural(counted.swaps, "swap") : nil
        let others = counted.others > 0 ? plural(counted.others, "rewrite") : nil
        return [swaps, others].compactMap { $0 }.joined(separator: ", ")
    }

    /// A count and the thing it counts, singular where there is one of it. "1 swaps" is the
    /// small wrongness that makes somebody stop trusting the rest of the number.
    private static func plural(_ count: Int, _ thing: String) -> String {
        "\(count) \(count == 1 ? thing : thing + "s")"
    }

    /// What a session in this folder is loaded with before it reads a word: the CLAUDE.md tree
    /// and what it costs.
    public static func context(tokens: Int, files: Int) -> String {
        guard files > 0 else { return "No CLAUDE.md" }
        return "~\(thousands(tokens)) in \(files) \(files == 1 ? "file" : "files")"
    }

    /// What is in the session's inbox that it has not picked up yet.
    public static func inbox(_ count: Int) -> String {
        count == 0 ? "Empty" : "\(count) waiting"
    }

    /// The model that answered its last request and how hard it was thinking, as one line.
    ///
    /// Nil where the session has not answered anything yet, which is a pane nobody has spoken to
    /// — and nil rather than a placeholder, so the tile simply says one thing instead of two.
    public static func answering(family: String?, effort: String?) -> String? {
        guard let family else { return nil }
        guard let effort, !effort.isEmpty else { return family }
        return "\(family) \(effort)"
    }

    /// Thousands, counted exactly as `ContextWindow.line` counts them — nobody reads the last
    /// three digits of either. A private copy of one line rather than a shared helper: the same
    /// rounding is already written twice in this repo, and widening one type's private detail
    /// into module surface to save a line is the trade that never pays.
    private static func thousands(_ count: Int) -> String {
        count < 1000 ? "\(count)" : "\(count / 1000)k"
    }
}
