import DeckhandKit
import SwiftUI

/// The sessions screen is utt's rail, full width: the mark, the daemon's state, and every
/// live Claude session as a row. Dark whatever the phone is set to, because the rail is
/// always the warm ground — that is the surface the whole language is built on.
struct SessionListView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                head
                groups
                foot
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.lcdGround)
            .environment(\.colorScheme, .dark)
            .navigationDestination(for: Session.self) { SessionView(model: model, session: $0) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshSessions()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// The mark and the one thing the person always needs: whether the Mac is there.
    private var head: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            HStack(alignment: .top) {
                DotMark(DotGlyph.anchor, size: 44, hotCore: 0.3)
                Spacer(minLength: 0)
                StatePill(model.connection.pill)
            }
            // The pill says which state it is in; this says why, and only when that adds
            // something. A line reading "Error" under a pill reading ERR is the pill twice.
            if let reason {
                Text(reason)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, Spacing.extraSmall)
        .padding(.bottom, Spacing.medium)
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
        .listRowSpacing(1)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
        .refreshable { await model.refreshSessions() }
    }

    /// Says which of the four empty states this is, rather than implying the Mac is idle.
    private var empty: some View {
        Text(emptyMessage)
            .font(Typography.railRow)
            .foregroundStyle(Palette.textSecondary)
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
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.extraSmall)
                    .padding(.bottom, Spacing.xxs)
            }
        }
    }

    private func row(_ session: Session) -> some View {
        let hidden = model.preferences.isHidden(session.name)
        return NavigationLink(value: session) {
            SessionRow(session: session, current: model.current == session.sessionId)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session-row")
        .swipeActions(edge: .leading) {
            Button(model.preferences.isFavorite(session.name) ? "Unstar" : "Star",
                   systemImage: "star") { model.toggleFavorite(session) }
                .tint(Palette.tint)
        }
        .swipeActions(edge: .trailing) {
            Button(hidden ? "Show" : "Hide", systemImage: hidden ? "eye" : "eye.slash") {
                model.setHidden(session, !hidden)
            }
            .tint(Palette.lcdGround)
        }
    }

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
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Palette.textSecondary)
        .padding(.top, Spacing.small)
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

/// One session as a rail row: its glyph on a tile, its name, its state.
private struct SessionRow: View {
    let session: Session
    let current: Bool

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            GlyphTile(DotGlyph.forName(session.name), size: 24, prominent: current)
            Text(session.name)
                .font(current ? Typography.railRowSelected : Typography.railRow)
                .foregroundStyle(current ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Spacing.extraSmall)
            StatePill(session.isBusy ? .busy : .idle)
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Color.primary.opacity(current ? 0.10 : 0))
        )
        .contentShape(.rect)
    }
}
