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
    /// Which pinned picture is being marked up, and whose card it is pinned to — the rail can be
    /// holding a card for more than one session, so the picture alone does not say.
    @State private var marking: Pinned?
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
                foot
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
            // On the page rather than on the row: a row is recycled as the listing refreshes, and
            // a sheet presented from one goes with it.
            .sheet(item: $marking) { SnapView(model: model, session: $0.session, snap: $0.snap) }
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
                send: { edited in Task { await model.send(edited, to: session) } },
                discard: { model.discard(for: session) },
                filtered: model.reviewFiltered[session.sessionId],
                compact: true,
                snaps: model.snaps(for: session),
                attach: { model.attach($0, to: session) },
                paste: { model.attachFromClipboard(to: session) },
                mark: { snap, said in
                    model.settle(said, for: session)
                    marking = Pinned(snap: snap, session: session)
                },
                commands: { await model.commands(for: session) }
            )
        }
    }

    private func star(_ session: Session) -> some View {
        let starred = model.preferences.isFavorite(session.name)
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
            // Only when there is nothing wrong. One line holds one of the two: what the Mac is
            // spending while it is fine, or what is broken about it — and the reason is a
            // sentence, so it is the thing that would be squeezed to an ellipsis by these.
            if reason == nil { Statusline(model: model) }
            StateWord(model.connection.state)
            Button("Hidden sessions", systemImage: model.showsHidden ? "eye" : "eye.slash") {
                model.showsHidden.toggle()
            }
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Palette.textTertiary)
        .padding(.horizontal, Spacing.small)
        // Even, so the mark sits in the middle of the band rather than at the foot of it. The
        // home indicator is the safe area's job now, not this padding's.
        .padding(.vertical, Spacing.small)
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
