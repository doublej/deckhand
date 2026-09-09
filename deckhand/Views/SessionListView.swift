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
    /// Pushed by hand rather than by a NavigationLink: a link inside a List draws the system's
    /// disclosure chevron outside the row's own fill, which broke the one edge this page has.
    @State private var chosen: Session?

    /// Everything on this page starts at the same left edge. A row's own padding is what its
    /// fill bleeds past that edge by, so the head, the group labels and a row's glyph line up
    /// while the rows still read as objects sitting on the ground rather than text on it.
    private static let gutter = Spacing.small

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                head
                groups
                foot
            }
            .padding(.horizontal, Self.gutter)
            .padding(.bottom, Spacing.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.lcdGround)
            .environment(\.colorScheme, .dark)
            .navigationDestination(item: $chosen) { SessionView(model: model, session: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshSessions()
                try? await Task.sleep(for: .seconds(4))
            }
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

    /// One line: the mark, whatever is wrong, and the state. It is the least important thing
    /// on the page and it is sized like it.
    private var head: some View {
        HStack(spacing: Spacing.extraSmall) {
            DotMark(DotGlyph.anchor, size: 20, hotCore: 0.3)
            // The pill says which state it is in; this says why, and only when that adds
            // something. A line reading "Error" under a pill reading ERR is the pill twice.
            if let reason {
                Text(reason)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.extraSmall)
            StatePill(model.connection.pill)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.top, Spacing.extraSmall)
        .padding(.bottom, Spacing.large)
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

    private func row(_ session: Session) -> some View {
        let hidden = model.preferences.isHidden(session.name)
        return Button { chosen = session } label: {
            SessionRow(
                session: session,
                current: model.current == session.sessionId,
                headline: model.headlines[session.sessionId],
                asks: model.tasks[session.sessionId] ?? []
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session-row")
        .swipeActions(edge: .leading) { star(session) }
        .swipeActions(edge: .trailing) { hide(session, hidden) }
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

    /// The other thin line. Settings are a place you go once; they do not need to look like
    /// anything from here.
    private var foot: some View {
        HStack(spacing: Spacing.medium) {
            Wordmark()
            Spacer(minLength: 0)
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

/// One session as a rail row: its glyph, its name, what it needs from you, and how far it has
/// got through what you asked.
///
/// The headline is the row. It is written to about twelve words, but a model writing prose is
/// not a layout engine — so the row gives it three lines and real leading rather than clipping
/// the one sentence the page exists to show.
private struct SessionRow: View {
    let session: Session
    let current: Bool
    /// What this session needs from you, in one line. Absent until the Mac has read it.
    let headline: String?
    /// What you have asked it for, as one dot each. Empty until the Mac has read it.
    let asks: [Ask]

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            GlyphTile(DotGlyph.forName(session.name), size: 32, prominent: current)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                title
                // The row is worth its extra height only when there is something in it; a
                // placeholder saying "reading…" on six rows at once is worse than nothing.
                if let headline {
                    Text(headline)
                        .font(Typography.subtitle)
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !asks.isEmpty {
                    AskDots(asks: asks).padding(.top, 2)
                }
                // How full its context is, as the shape alone: the number belongs on the
                // session's own page, and what a row needs to say is "this one is nearly
                // out of room" without spending a line on it.
                if let context = session.context {
                    Meter(context.share, tint: Palette.pressure(context.pressure), thickness: 2)
                        .padding(.top, Spacing.xxs)
                }
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Color.primary.opacity(current ? 0.11 : 0.045))
        )
        .contentShape(.rect)
    }

    /// The name and the state on one baseline, so the headline below them has the full width.
    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
            Text(session.name)
                .font(Typography.primaryRow)
                .fontWeight(current ? .semibold : .medium)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Spacing.extraSmall)
            StatePill(session.isBusy ? .busy : .idle)
        }
    }
}
