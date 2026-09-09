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
    @State private var recorder = Recorder()
    /// Which session the microphone is open for, if any. One recorder, many rows.
    @State private var talking: String?
    /// Pushed by hand rather than by a NavigationLink: a link inside a List draws the system's
    /// disclosure chevron outside the row's own fill, which broke the one edge this page has.
    @State private var chosen: Session?
    @Environment(\.scenePhase) private var phase

    /// Everything on this page starts at the same left edge. A row's own padding is what its
    /// fill bleeds past that edge by, so the head, the group labels and a row's glyph line up
    /// while the rows still read as objects sitting on the ground rather than text on it.
    private static let gutter = Spacing.small

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                groups
                foot
            }
            .padding(.horizontal, Self.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.lcdGround)
            // The whole glass, not the safe area. This screen is a terminal and a terminal runs
            // to its own edges; the rows keep the page's one gutter and nothing else.
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
            .navigationDestination(item: $chosen) { SessionView(model: model, opened: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshSessions()
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
        // Its own loop, slower than the listing's: a headline is a model reading a transcript,
        // not a field on the session. Prefetching them here also means a session you then open
        // already has its briefing written.
        .task {
            while !Task.isCancelled {
                await model.loadHeadlines()
                try? await Task.sleep(for: .seconds(45))
            }
        }
    }

    /// What the pill cannot carry: the reason. Nothing at all when the Mac is simply there.
    private var reason: String? {
        switch model.connection {
        case .connected(let iterm): iterm == "ok" ? nil : iterm
        default: model.status ?? model.connection.label
        }
    }

    /// A List rather than a stack, only so a row can still be swiped to star or hide.
    private var groups: some View {
        List {
            if model.visibleSessions.isEmpty { empty.plainRow() }
            group("Favourites", model.visibleSessions.filter { model.preferences.isFavorite($0.name) })
            group("Sessions", model.visibleSessions.filter { !model.preferences.isFavorite($0.name) })
        }
        .listStyle(.plain)
        .listRowSpacing(Spacing.extraSmall)
        .listSectionSeparator(.hidden)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable { await model.refreshSessions() }
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

    @ViewBuilder private func group(_ title: String, _ sessions: [Session]) -> some View {
        if !sessions.isEmpty {
            Section {
                ForEach(sessions) { row($0).plainRow() }
            } header: {
                Text(title.uppercased())
                    .font(Typography.groupLabel)
                    .tracking(0.6)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, Spacing.small)
                    .padding(.bottom, Spacing.extraSmall)
            }
        }
    }

    /// Tap a row to open it, hold one to talk to it without opening it at all — which is the
    /// whole point of a list of six sessions: answering the one that needs a word is a press,
    /// not a page. What it heard appears under the row it was said to.
    private func row(_ session: Session) -> some View {
        let hidden = model.preferences.isHidden(session.name)
        return VStack(spacing: Spacing.xxs) {
            TalkControl(
                recorder: recorder,
                mode: model.preferences.talkMode,
                isMine: talking == session.sessionId,
                pressToStart: true,
                onTap: { chosen = session },
                onStart: { startTalking(to: session) },
                onClip: { await heard($0, for: session) },
                content: { open(session, $0) }
            )
            review(for: session)
        }
        .swipeActions(edge: .leading) { star(session) }
        .swipeActions(edge: .trailing) { hide(session, hidden) }
    }

    private func startTalking(to session: Session) {
        talking = session.sessionId
        model.status = "Recording for \(session.name)"
    }

    private func heard(_ clip: URL, for session: Session) async {
        await model.upload(clip: clip, to: session)
        talking = nil
    }

    /// The row, and every tap on it. Deliberately not a `Button`: a button takes the touch
    /// before the press that starts talking ever sees it. What a tap means is the talk
    /// control's to say — open this session, or send what it just heard.
    private func open(_ session: Session, _ talk: TalkState) -> some View {
        SessionRow(
            session: session,
            current: model.current == session.sessionId,
            headline: model.headlines[session.sessionId],
            asks: model.tasks[session.sessionId] ?? [],
            talk: talk
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("session-row")
    }

    /// What it heard, under the row it was heard for. Sitting anywhere else it would be a card
    /// that names a session rather than one belonging to it.
    @ViewBuilder private func review(for session: Session) -> some View {
        if let text = model.review[session.sessionId] {
            ReviewCard(
                text: text,
                target: session.name,
                send: { Task { await model.send(text, to: session) } },
                discard: { model.discard(for: session) },
                compact: true
            )
        }
    }

    private func star(_ session: Session) -> some View {
        Button(model.preferences.isFavorite(session.name) ? "Unstar" : "Star",
               systemImage: "star") { model.toggleFavorite(session) }
            .tint(Palette.tint)
    }

    private func hide(_ session: Session, _ hidden: Bool) -> some View {
        Button(hidden ? "Show" : "Hide", systemImage: hidden ? "eye" : "eye.slash") {
            model.setHidden(session, !hidden)
        }
        .tint(Palette.lcdGround)
    }

    /// The one thin line on the page, and now the only chrome on it: the mark, whatever is
    /// wrong, the daemon's state, and the two places you can go. It was two lines, one at each
    /// end, and the top one spent a band of the screen saying what this one already says.
    private var foot: some View {
        HStack(spacing: Spacing.small) {
            Wordmark()
            if let reason {
                Text(reason)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.extraSmall)
            StatePill(model.connection.pill)
            Button("Hidden sessions", systemImage: model.showsHidden ? "eye" : "eye.slash") {
                model.showsHidden.toggle()
            }
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Spacing.small)
        .padding(.top, Spacing.medium)
        // Clear of the home indicator, since the screen itself no longer is.
        .padding(.bottom, Spacing.medium)
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
