import DeckhandKit
import SwiftUI

/// Where a session's page opens: one grid saying everything true of it, and a way into everything
/// you can do to it.
///
/// It replaced three panes and most of a menu. Slips, files and orders were three swipes of the
/// five, each of them a screen you had to arrive at to find out whether it had anything on it —
/// and rename, the filter chain and the project's settings were behind a glyph in the corner, in
/// a list of words with no numbers beside any of them. The grid answers both: a square carries
/// the count and three lines of what the count is *of*, so the page says what is waiting before
/// anything is opened, and the thing it opens is the pane or the sheet that already existed.
///
/// **A square names things; it does not draw them.** A tile lists three slip titles, three
/// filenames, three subagent descriptions — one line of plain text each, which is the difference
/// between a preview and a second copy of a pane. Nothing here renders a slip's page, a file's
/// contents or a paragraph of orders: `ArtifactsView`, `FilesView` and `OrdersView` are untouched
/// and arrive on a sheet, and that is still the rule the whole page is built on.
///
/// What stayed a swipe is the reading: this, the briefing, the transcript. Those three are things
/// you *read*, one after another, and paging between them with a thumb is the whole reason the
/// tab bar could go. Everything else is something you *do*, once, and a thing done once belongs
/// behind a tap rather than in a carousel you have to swipe past on the way to the transcript.
struct DashboardView: View {
    @Bindable var model: AppModel
    let session: Session
    /// The page's own recorder, lent to the sheets with a field on them, exactly as the menu's
    /// sheets were lent it before. A sheet that made its own would record while this page stayed
    /// teal — see `SessionView.say`.
    let say: Dictation
    /// Which of the folded panes is open. Held by the page rather than here because the manager
    /// can ask for one by name before anybody has looked at this view — see `SessionView.show`.
    @Binding var opened: DashboardDestination?

    /// The standing orders, this view's own, exactly as `OrdersView` keeps its own: it is one
    /// screen's state and nothing else in the app wants it. Nil until the Mac answers, so a tile
    /// never says "None standing" about a session it has not asked about yet.
    @State var orders: Orders?
    /// The CLAUDE.md tree, for the one tile that is about what a session started with.
    @State var docs: ContextDocs?
    /// Everything being done to words on their way in: how much of it there is, and which chain
    /// steps are doing their part of it. Not the rows themselves, which carry each step's
    /// settings and are `Swapping`'s to edit against the model.
    ///
    /// Nil until **both** halves have arrived — the chain and this Mac's alias list. A number
    /// tallied before the aliases are asked for is confidently smaller than the truth, which is
    /// worse than the "…" it would have replaced.
    @State var chain: Incoming?
    /// A document opened out of the context tree. Its sheet is declared *inside* the context
    /// sheet's content, not here: a view presents one sheet at a time, and a second one attached
    /// to this view would have nowhere to go while the first is up.
    @State var doc: Asset?
    /// Asked for once, when the page is built. Nobody watches any of these change, and three of
    /// the four are a walk on the Mac rather than a field on the session.
    @State private var asked = false
    /// The page's colour, which goes utt orange while the mark at the foot of it is open.
    @Environment(\.accent) var accent

    /// Words on their way in, as a square needs them: how much is in force across every scope,
    /// and which chain steps are switched on, by name.
    struct Incoming: Equatable {
        let counted: Replacements.Tally
        let running: [String]
    }

    var body: some View {
        // The width the squares have to divide, measured rather than assumed: this page is the
        // same view upright and on its side, and a phone on its side is more than twice as wide.
        GeometryReader { space in
            ScrollView {
                LazyVGrid(columns: across(space.size.width), spacing: Spacing.small) {
                    tiles
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.top, Spacing.medium)
                .padding(.bottom, Spacing.extraLarge)
            }
            .fadingEdges()
            // Room at the end for the mark that floats over this.
            .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
        }
        .task { await load() }
        .sheet(item: $opened) { page(for: $0) }
    }

    /// How many squares fit across, and the gutter between them. The count is `Dashboard`'s,
    /// where `just test` can hold the thresholds down; the columns themselves are flexible, so
    /// the arithmetic that turns a width into a tile size stays SwiftUI's.
    ///
    /// **Top-aligned, which is what lets a tile be honestly short.** Tiles are no longer squares
    /// and no longer a fixed height — one carrying three filenames is taller than one saying
    /// "None standing" and nothing else. Centred, the short one would float in the middle of its
    /// row with a gap above and below; aligned to the top, the whole difference falls underneath
    /// it and reads as the gutter it is.
    private func across(_ width: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Spacing.small, alignment: .top),
              count: Dashboard.columns(across: width))
    }

    /// The folder this session is working in, built here rather than looked up in the picker's
    /// catalog: that page wants a path and a name, this session has both, and a folder with no
    /// atlas record is still a folder whose settings somebody may want to change.
    var here: Project { Project(name: session.folder, path: session.cwd) }

    /// What each tile is opened onto. Three of these are the panes that used to be swiped to,
    /// three are the sheets the menu used to open, and the agents were reachable only by finding
    /// the right row in the transcript. Every one of them is the view that already existed.
    @ViewBuilder private func page(for destination: DashboardDestination) -> some View {
        switch destination {
        case .slips: framed("Slips") { ArtifactsView(model: model, session: session) }
        case .agents: framed("Agents") { AgentList(model: model, session: session) }
        case .files: framed("Files") { FilesView(model: model, session: session) }
        case .orders: framed("Orders") { OrdersView(model: model, session: session, say: say) }
        case .context: framed("Context") { tree }
        // Everything that rewrites what was said, in the order it runs — utt's hints, this Mac's
        // word list and this session's chain — rather than the chain alone. The square's label
        // was already the wider question ("On the way in"), and the chain editor is one press
        // further in from here rather than gone: `Swapping` presents `SessionFilters` itself.
        case .filters: Swapping(model: model, session: session, say: say)
        case .project: ProjectSettingsView(model: model, project: here)
        case .name: rename
        }
    }

    /// A pane put on a sheet: the page's own ground, its name at the top, and one way off it.
    ///
    /// The three panes it wraps were written to sit under `SessionHead`, which named the session
    /// and nothing else — so on a sheet they would arrive with no title at all. The other three
    /// destinations carry their own `NavigationStack` already and are not wrapped.
    private func framed(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack {
            content()
                .background(Palette.surfaceGround)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { opened = nil }.tint(Palette.tint)
                    }
                }
        }
    }

    /// The CLAUDE.md tree, with the file viewer attached to it rather than to this page — see
    /// `doc`. Until now the tree was reachable only through a chip at the top of the files pane,
    /// which is a long way from "what is this session loaded with".
    private var tree: some View {
        ContextTree(context: docs ?? ContextDocs()) { doc = $0 }
            .sheet(item: $doc) { AssetView(model: model, session: session, asset: $0) }
    }

    private var rename: some View {
        Renaming(session: session, say: say) { wanted in
            Task { await model.rename(session, to: wanted) }
        }
    }

    /// Everything the squares need that the listing does not already carry, once.
    ///
    /// They go **together**. Awaited one after another they arrived over about ten seconds and
    /// the grid sat on four "…" for most of it — which is the one thing a dashboard must not do,
    /// since a square with no number on it is exactly the square this page exists to replace.
    /// The two client calls still go through `model.run`, so a Mac that will not answer says so
    /// in the same status line as everything else; the three model calls report themselves.
    ///
    /// The slips are the one thing here asked for twice over. Their two *counts* ride on every
    /// listing (`Session.artifactsWaiting`) and are therefore fresher than this could ever be, so
    /// the number on that square is still the listing's. What this fetches is the titles under
    /// it, which no listing carries — and it is the same directory read `ArtifactsView` makes
    /// when the square is opened, so nothing new was put on the wire for it.
    private func load() async {
        guard !asked, let client = model.settings.client() else { return }
        asked = true
        async let heard = try? client.aliases()
        async let touched: Void = model.loadFiles(for: session)
        async let written: Void = model.loadArtifacts(for: session)
        async let tree = model.context(for: session)
        var offer: (known: [Filter], steps: [FilterStep])?
        await model.run {
            async let standing = client.orders(of: session.sessionId)
            async let offered = client.filters(of: session.sessionId)
            orders = try await standing
            offer = try await offered
        }
        // Both halves, or neither. A tally over a list that was never fetched — or fetched and
        // refused — is confidently smaller than the truth, and "2 swaps" at a Mac with fourteen
        // is worse than the "Nothing running" this replaced: a person can tell that "nothing"
        // might mean "not asked" and cannot tell that about a number.
        if let offer, let aliases = await heard { chain = incoming(offer, aliases) }
        await touched
        await written
        docs = await tree
    }

    /// What the square about words on their way in knows, once the chain and this Mac's alias
    /// list are both here.
    ///
    /// The tally is `Replacements`' own, which is the point: the number on the square and the
    /// listing `Swapping` draws behind it are the one function, so they cannot drift apart.
    ///
    /// The aliases are handed in rather than read off `model.wants`, and that is the guard
    /// rather than a style choice. `AppModel.loadAliases` answers a refused request by leaving
    /// the list exactly as it found it, so a Mac that would not answer and a Mac with no aliases
    /// are the same empty array on the model — and this square would report the second when the
    /// first is true. Asked for here, a failure is `nil` and the square goes on saying "…".
    private func incoming(_ offer: (known: [Filter], steps: [FilterStep]),
                          _ aliases: [Alias]) -> Incoming {
        let stages = Replacements.inForce(aliases: aliases,
                                          chain: offer.steps,
                                          known: offer.known)
        return Incoming(counted: Replacements.tally(stages),
                        running: Dashboard.running(offer.steps, over: offer.known))
    }
}

/// What a tile opens. Top level rather than nested, because the page holds it: the manager can
/// ask for "slips" before this view has ever been on screen, and the ask has to land somewhere
/// that survives the pane being rebuilt.
enum DashboardDestination: String, Identifiable, CaseIterable {
    case slips, agents, files, orders, filters, context, project, name

    var id: String { rawValue }
}
