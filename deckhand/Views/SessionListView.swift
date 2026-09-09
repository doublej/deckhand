import DeckhandKit
import SwiftUI

/// The deck: every Claude session running in an iTerm pane on the Mac, favourites first.
struct SessionListView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ConnectionBar(connection: model.connection, status: model.status)
                list
            }
            .background(.black)
            .navigationDestination(for: Session.self) { SessionView(model: model, session: $0) }
            .navigationTitle("deckhand")
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(model.showsHidden ? "Hide hidden" : "Show hidden",
                           systemImage: model.showsHidden ? "eye.slash" : "eye") {
                        model.showsHidden.toggle()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Pair", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        }
    }

    private var list: some View {
        List {
            if model.visibleSessions.isEmpty {
                Text(emptyMessage)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.black)
            }
            section("favourites", model.visibleSessions.filter { model.preferences.isFavorite($0.name) })
            section("sessions", model.visibleSessions.filter { !model.preferences.isFavorite($0.name) })
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refreshSessions() }
        .task {
            while !Task.isCancelled {
                await model.refreshSessions()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// Says which of the three empty states this is, rather than implying the Mac is idle.
    private var emptyMessage: String {
        switch model.connection {
        case .unpaired: "Pair with your Mac first — tap the gear"
        case .checking: "Looking for sessions…"
        case .failed(let why): why
        case .connected: model.sessions.isEmpty
            ? "No Claude sessions running in iTerm"
            : "Every session is hidden — tap the eye to show them"
        }
    }

    @ViewBuilder private func section(_ title: String, _ sessions: [Session]) -> some View {
        if !sessions.isEmpty {
            Section {
                ForEach(sessions) { row($0) }
            } header: {
                Text(title)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ session: Session) -> some View {
        let hidden = model.preferences.isHidden(session.name)
        return NavigationLink(value: session) { SessionRow(session: session) }
            .accessibilityIdentifier("session-row")
            .listRowBackground(Color.black)
            .swipeActions(edge: .leading) {
                Button(model.preferences.isFavorite(session.name) ? "Unstar" : "Star",
                       systemImage: "star") { model.toggleFavorite(session) }
                    .tint(.white.opacity(0.2))
            }
            .swipeActions(edge: .trailing) {
                Button(hidden ? "Show" : "Hide", systemImage: hidden ? "eye" : "eye.slash") {
                    model.setHidden(session, !hidden)
                }
                .tint(.white.opacity(0.2))
            }
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(session.isBusy ? .white : .white.opacity(0.25))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                Text(session.folder)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.lastActive, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
