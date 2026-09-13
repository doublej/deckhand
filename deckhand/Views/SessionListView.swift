import DeckhandKit
import SwiftUI

/// The sessions screen is utt's rail, full width: the mark, the daemon's state, and every
/// live Claude session as a row. Dark whatever the phone is set to, because the rail is
/// always the warm ground — that is the surface the whole language is built on.
///
/// The page is about the sessions and nothing else. The mark, the daemon's state and the
/// settings are one thin line at each end, small and quiet on purpose; everything between
/// them belongs to the sessions, which are given the room to say what they need.
struct SessionListView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false
    /// The project picker. Its own sheet rather than a page pushed onto the rail: it is a way
    /// *into* a session rather than a place, and it hands one back rather than navigating.
    @State private var showProjects = false
    @State private var recorder = Recorder()
    /// Which session the microphone is open for, if any. One recorder, many rows.
    @State private var talking: String?
    /// Pushed by hand rather than by a NavigationLink: a link inside a List draws the system's
    /// disclosure chevron outside the row's own fill, which broke the one edge this page has.
    @State private var chosen: Session?
    @Environment(\.scenePhase) private var phase

    /// What this page's accents are drawn in. Read here rather than from the environment because
    /// this is the view that puts it there, and a view never sees what it hands its own children.
    private var accent: Color { Palette.accent(recording: recorder.isRecording) }

    /// Everything on this page starts at the same left edge. A row's own padding is what its
    /// fill bleeds past that edge by, so the head, the group labels and a row's glyph line up
    /// while the rows still read as objects sitting on the ground rather than text on it.
    private static let gutter = Spacing.small

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                groups
                RailFoot(model: model, showSettings: $showSettings, showProjects: $showProjects)
            }
            .padding(.horizontal, Self.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The ground runs to the glass; what is written on it does not. A terminal fills
            // its screen, but the first line of one is not printed under the clock — this used
            // to ignore the safe area for the whole page, which put SESSIONS behind the time
            // and the wordmark on the home indicator. Ignoring it for the ink was never the
            // point; ignoring it for the ground is, and the inset is the phone's own, so it is
            // right on every one of them rather than right on the one I looked at.
            .background(Palette.lcdGround.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
            // The whole rail goes utt orange while a row is listening, not only the row: one
            // decision, made here, that every accent inside the page reads out of the
            // environment. It is the recorder's own state, so the page is teal again the
            // instant the clip is sent, thrown away, refused or interrupted.
            .accent(accent)
            .navigationDestination(item: $chosen) { SessionView(model: model, opened: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
            // The rail owns where you end up, so the picker hands the new session back rather
            // than pushing anything itself — same route a tapped row takes.
            .sheet(isPresented: $showProjects) {
                ProjectListView(model: model) { chosen = $0 }
            }
            // Where the manager has asked this phone to go. The gate is this page's own
            // `@State`, so this page is the only thing that can move it — the desk holds the
            // ask and hands it over, which is the whole of the app's command surface today.
            .onChange(of: model.manager.route) { _, route in
                guard let route else { return }
                model.manager.route = nil
                switch route {
                case .session(let id): chosen = model.sessions.first { $0.sessionId == id }
                case .list: chosen = nil
                case .settings: showSettings = true
                case .projects: showProjects = true
                case .refresh: Task { await model.refreshSessions() }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshSessions()
                await model.refreshLinks()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        // Coming back to the app is the one moment the four-second loop cannot cover: it was
        // suspended while you were away, so what is on screen is as old as your trip — and a
        // session that compacted while you were gone is exactly what you came back to see.
        .onChange(of: phase) { _, now in
            guard now == .active else { return }
            Task { await model.refreshSessions() }
        }
        // Its own loop, and one call for every session rather than one each. The Mac writes
        // these on its own cycle and keeps them on disk, so this reads rather than commissions:
        // the first sweep after a cold start fills the whole rail and costs nothing.
        .task {
            while !Task.isCancelled {
                await model.loadBriefings()
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }

    /// A List rather than a stack, only so a row can still be swiped to star or hide.
    ///
    /// Sessions messaging each other are drawn *behind* it, off the rows' own anchors, so the
    /// picture follows the list as it scrolls and a session that scrolls away simply stops
    /// having a thread. Nothing here knows a row height or an offset.
    private var groups: some View {
        List {
            if model.visibleSessions.isEmpty { empty.plainRow() }
            ForEach(model.projects) { block($0) }
        }
        .listStyle(.plain)
        // A hairline, so the sessions of one project read as one slab. What separates two
        // projects is the header between them, not a gap between their rows.
        .listRowSpacing(1)
        .listSectionSeparator(.hidden)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable {
            await model.refreshSessions()
            await model.refreshLinks()
        }
        .backgroundPreferenceValue(SessionNodes.self) { nodes in
            GeometryReader { proxy in
                SessionLinkTrails(
                    trails: model.trails,
                    window: model.preferences.linkWindow,
                    nodes: nodes.mapValues { proxy[$0] }
                )
            }
            // Reclaims the page's own side margin for the threads to bow into. A background
            // takes no room, so this costs the list nothing and is the difference between an
            // arc between two sessions and a wire running down the edge of the screen.
            .padding(.leading, -Self.gutter)
        }
    }

    /// Says which of the four empty states this is, rather than implying the Mac is idle.
    private var empty: some View {
        Text(emptyMessage)
            .font(Typography.primaryRow)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.large)
    }

    private var emptyMessage: String {
        switch model.connection {
        case .unpaired: "Not paired yet — open settings and give it the Mac's address"
        case .checking: "Looking for sessions…"
        case .failed(let why): why
        case .connected: model.sessions.isEmpty
            ? "No Claude sessions running on the Mac"
            : "Every session is hidden — the eye below brings them back"
        }
    }

    /// One project as a block: the folder and where it sits said once above it, then its
    /// sessions stuck together as a single slab with hairline seams.
    private func block(_ project: ProjectGroup) -> some View {
        Section {
            ForEach(Array(project.sessions.enumerated()), id: \.element.id) { index, session in
                row(session, first: index == 0, last: index == project.sessions.count - 1)
                    .plainRow()
            }
        } header: {
            ProjectHeader(
                project: project,
                machine: model.namesMachines ? model.label(of: project.machine) : ""
            )
        }
    }

    /// Tap a row to open it, hold one to talk to it without opening it at all — which is the
    /// whole point of a list of six sessions: answering the one that needs a word is a press,
    /// not a page. What it heard appears under the row it was said to.
    private func row(_ session: Session, first: Bool, last: Bool) -> some View {
        let hidden = model.preferences.isHidden(session)
        return VStack(spacing: Spacing.xxs) {
            TalkControl(
                recorder: recorder,
                mode: model.preferences.talkMode,
                isMine: talking == session.sessionId,
                pressToStart: true,
                onTap: { chosen = session },
                onStart: { startTalking(to: session) },
                onClip: { await heard($0, for: session) },
                content: { open(session, $0, first: first, last: last) }
            )
            review(for: session)
        }
        // Both on the leading edge, and that is not a tidy-up: a trailing swipe is how the
        // manager panel is pulled in from anywhere on the rail now (`ManagerShell`), so a row
        // that answered to one would be arguing with the screen. One swipe, one edge, both
        // actions — and the drag going the other way belongs to nothing on this page.
        .swipeActions(edge: .leading) {
            star(session)
            hide(session, hidden)
        }
    }

    private func startTalking(to session: Session) {
        talking = session.sessionId
        model.report("Recording for \(session.name)", to: session)
    }

    private func heard(_ clip: URL, for session: Session) async {
        await model.upload(clip: clip, to: session, spans: recorder.spans)
        talking = nil
    }

    /// The row, and every tap on it. Deliberately not a `Button`: a button takes the touch
    /// before the press that starts talking ever sees it. What a tap means is the talk
    /// control's to say — open this session, or send what it just heard.
    private func open(_ session: Session, _ talk: TalkState, first: Bool, last: Bool) -> some View {
        SessionRow(
            session: session,
            current: model.current == session.sessionId,
            headline: model.headlines[session.sessionId],
            asks: model.tasks[session.sessionId] ?? [],
            talk: talk,
            confirms: model.preferences.confirms,
            spoken: model.spoken(for: session),
            starred: model.preferences.isFavorite(session),
            first: first,
            last: last
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("session-row")
    }

    /// What it heard, under the row it was heard for, and the two answers this screen can give
    /// about it: send it as it stands, or open the session and work on it there.
    ///
    /// Sitting anywhere else it would be a row that names a session rather than one belonging to
    /// it. The card itself stays on the session's page and is what Refine opens — see
    /// `SendOrRefine`, which is also where the reason nothing is handed over is written down.
    @ViewBuilder private func review(for session: Session) -> some View {
        if let text = model.review[session.sessionId] {
            SendOrRefine(
                words: text,
                target: session.name,
                refusal: model.reviewFiltered[session.sessionId]?.refusal,
                send: { edited in Task { await model.send(edited, to: session) } },
                // The same push a tap on the row makes, and deliberately not `manager.route`:
                // this view owns `chosen`, and the route exists for asks arriving from outside
                // the phone. What lands there is the card, already holding these words.
                refine: { chosen = session }
            )
        }
    }

    private func star(_ session: Session) -> some View {
        let starred = model.preferences.isFavorite(session)
        // The glyph says what the swipe will do, like the word beside it. It was `star` either
        // way, so on a starred row the action and its icon disagreed.
        return Button(starred ? "Unstar" : "Star",
                      systemImage: starred ? "star.slash" : "star") {
            model.toggleFavorite(session)
        }
        .tint(accent)
    }

    private func hide(_ session: Session, _ hidden: Bool) -> some View {
        Button(hidden ? "Show" : "Hide", systemImage: hidden ? "eye" : "eye.slash") {
            model.setHidden(session, !hidden)
        }
        .tint(Palette.lcdGround)
    }

}

private extension View {
    /// A list row that gets out of the way: the rail draws its own ground and its own spacing.
    func plainRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }
}
