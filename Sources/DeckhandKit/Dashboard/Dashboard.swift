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

    /// The files worth naming under the count, most recently touched first. The name alone —
    /// a square is not wide enough for a path, and the pane behind the square has the path.
    public static func touched(_ found: [Asset]) -> [String] {
        few(found.sorted { $0.modified > $1.modified }).map(\.name)
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

    /// The chain: how many steps run, out of everything this Mac can do to words on the way in.
    ///
    /// Both halves, because one is not a fact on its own — "3 running" says nothing about whether
    /// that is most of them or a corner of what is available.
    public static func chain(running: Int, of offered: Int) -> String {
        if offered == 0 { return "None offered" }
        return running == 0 ? "Nothing running" : "\(running) of \(offered) running"
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
