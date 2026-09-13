import DeckhandKit
import SwiftUI

/// The squares themselves, and the order they are read in.
///
/// Split from the page for the 300-line gate, and the seam is a real one: the page is a grid, a
/// loader and seven destinations, and none of that changes when a tile is added. What a tile
/// *says* is `Dashboard`, one module over, where `just test` can prove it.
extension DashboardView {
    /// The grid, in reading order, and the order is the argument.
    ///
    /// What is waiting on you first — a slip with no answer beside it is the session stopped —
    /// and then what the session is doing without you, which is its subagents.
    /// Then what it made, what it is running under and what it started with, which is the rest of
    /// "where am I". Compact closes that half rather than opening the next one, because it is a
    /// reading before it is a button: the figure on it is the window, and the press is only what
    /// you do about the figure. Then the four things you change about the session, and Stop last,
    /// where a thumb crossing the grid quickly reaches it slowest.
    ///
    /// The two controls that cannot be undone are not here at all: they stayed in the menu,
    /// grouped and red, because a grid of identical squares is exactly where a mis-tap costs the
    /// most. See `DashboardView+Doing`.
    @ViewBuilder var tiles: some View {
        slipsTile
        agentsTile
        filesTile
        ordersTile
        chainTile
        contextTile
        windowTile
        projectTile
        nameTile
        macTile
        inboxTile
        stopTile
    }

    /// The slips, waiting ones first. The two counts ride on every listing, so the number is as
    /// fresh as the rail is; the titles under it are the one thing here that costs a request,
    /// and it is the same directory listing the slips pane makes when it opens.
    var slipsTile: some View {
        DashboardTile(glyph: "questionmark.bubble",
                      title: "Slips",
                      value: Dashboard.slips(waiting: session.waitingPages,
                                             answered: session.answeredPages),
                      preview: Dashboard.asking(model.artifacts[session.sessionId] ?? []),
                      lit: session.waitingPages > 0 ? accent : nil) { opened = .slips }
    }

    /// How many subagents are working right now, and the way into all of them.
    ///
    /// It costs no request of its own: `model.agents` is refreshed at the tail of every
    /// `loadTurns`, which the session page already polls every five seconds whichever pane is
    /// showing — so this square is as fresh as the transcript is.
    ///
    /// Dimmed when the session has never started one, because there is nothing to drill into.
    /// `model.agents` is also empty against a Mac too old to serve the route, and `loadAgents`
    /// already decided those two are the same answer: none.
    var agentsTile: some View {
        let running = model.agents.values.filter(\.running).count
        return DashboardTile(glyph: "arrow.triangle.branch",
                             title: "Agents",
                             value: Dashboard.agents(running: running,
                                                     finished: model.agents.count - running),
                             preview: Dashboard.doing(Array(model.agents.values)),
                             lit: running > 0 ? accent : nil,
                             ready: !model.agents.isEmpty,
                             spoken: "Subagents") { opened = .agents }
    }

    /// What the session made. The listing says nothing about files, so this one waits for its
    /// own request rather than claiming "None yet" about a folder it has not looked in.
    var filesTile: some View {
        let touched = model.assets[session.sessionId]
        return DashboardTile(glyph: "doc.on.doc",
                             title: "Files",
                             value: touched.map { Dashboard.files($0.count) } ?? "…",
                             preview: Dashboard.touched(touched ?? [])) { opened = .files }
    }

    /// The standing orders, opened on their first written line — which is the whole reason this
    /// is a tile and was a pane: the question "is this session running under orders, and which"
    /// used to cost a swipe to the far end of the carousel to answer.
    var ordersTile: some View {
        DashboardTile(glyph: "list.bullet.clipboard",
                      title: "Orders",
                      value: orders.map { Dashboard.orders($0.text) } ?? "…",
                      preview: Dashboard.rest(of: orders?.text ?? ""),
                      lit: orders?.inForce == true ? accent : nil) { opened = .orders }
    }

    /// Everything being done to this session's words on their way in, counted over every scope.
    ///
    /// The number is the whole cascade — utt's hints, this Mac's alias list and the chain — and
    /// not the chain alone, which is what it counted first. A person with twelve aliases
    /// rewriting every clip and no chain step switched on read "Nothing running" and believed
    /// it, and that sentence is the exact misreading the screen behind this square was built to
    /// end. The preview stays the chain's steps, which is the half a square has room to name.
    var chainTile: some View {
        DashboardTile(glyph: "line.3.horizontal.decrease",
                      title: "On the way in",
                      value: chain.map { Dashboard.swapping($0.counted) } ?? "…",
                      preview: Dashboard.few(chain?.running ?? []),
                      spoken: "Words on the way in") { opened = .filters }
    }

    /// What a session in this folder is loaded with before it reads a word. The tree was
    /// reachable only through a chip at the top of the files pane, which is a long way from the
    /// question it answers.
    var contextTile: some View {
        // Not one of the three-line glyphs: the filter square beside it is already
        // `line.3.horizontal.decrease`, and at 12pt the two were the same picture.
        DashboardTile(glyph: "doc.text",
                      title: "Context",
                      value: docs.map {
                          Dashboard.context(tokens: $0.tokens, files: $0.documents.count)
                      } ?? "…",
                      // No caption any more. It read "Every CLAUDE.md it started with", which is
                      // a sentence explaining the tile rather than a fact about the session —
                      // the one thing this grid's own rule forbids — and it was only there
                      // because the square had nothing else in it. The three folder names say
                      // what it is, and they are true.
                      //
                      // In the tree's own order, which is the order a session reads them in.
                      // The label rather than the path: every one of these is a CLAUDE.md, so
                      // the folder it speaks for is the only part that tells them apart.
                      preview: Dashboard.few(docs?.documents ?? []).map(\.label)) {
            opened = .context
        }
    }

    /// How much window is left, what is spending it, and the one thing to do about it.
    ///
    /// The header carries the same share as a 13pt ring on every pane; this says it in figures
    /// with the model beside it and, unlike the ring, it is the button that acts on it. Compact
    /// is the only control on the grid that changes the conversation, and it is here rather than
    /// among the other keystrokes because the number that decides whether to press it is the
    /// number printed on it.
    var windowTile: some View {
        DashboardTile(glyph: Control.compact.symbol,
                      title: "Compact",
                      value: session.context?.line ?? "Not read yet",
                      // The caveat wins over the model when there is one: a dimmed square with
                      // no sentence on it is a square nobody can act on.
                      caption: needsPane ?? Dashboard.answering(family: session.family,
                                                                effort: session.effort),
                      // The one square whose fact is a share, so the one square with a bar.
                      // "372k of 450k" is arithmetic; the bar has already done it.
                      meter: session.context?.share,
                      lit: session.context.map { Palette.pressure($0.pressure) },
                      ready: hasPane,
                      spoken: Control.compact.label) { run(.compact) }
    }

    /// The folder, and everything this Mac has been told it may do about the work in it. Keyed
    /// by the path, which outlives every session in it.
    var projectTile: some View {
        DashboardTile(glyph: "slider.horizontal.3",
                      title: "Project",
                      value: session.folder,
                      caption: parent.map { "in \($0)" },
                      spoken: "Project settings") { opened = .project }
    }

    /// The folder one level up, which is most of what tells two `web` folders apart. Nil at the
    /// root, and nil rather than a slash — a caption reading "in /" is noise.
    private var parent: String? {
        let above = (session.cwd as NSString).deletingLastPathComponent
        let name = (above as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
