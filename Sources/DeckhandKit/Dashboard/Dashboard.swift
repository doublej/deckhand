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

    /// The first line of the standing orders, which is as much as a square has room for.
    ///
    /// The first *non-empty* line: orders are dictated as often as they are typed, and a
    /// paragraph that opens on a blank line would otherwise put an empty tile over a session
    /// running under orders — the one lie this tile must not tell.
    public static func orders(_ text: String) -> String {
        let written = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return written ?? "None standing"
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
