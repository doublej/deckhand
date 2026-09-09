import DeckhandKit
import SwiftUI

/// The deck: every Claude session running in an iTerm pane on the Mac.
struct SessionListView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                if model.sessions.isEmpty {
                    Text(model.isConfigured ? "No live sessions" : "Pair with your Mac first")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.black)
                }
                ForEach(model.sessions) { session in
                    NavigationLink(value: session) {
                        SessionRow(session: session)
                    }
                    .listRowBackground(Color.black)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(.black)
            .navigationDestination(for: Session.self) { SessionView(model: model, session: $0) }
            .navigationTitle("deckhand")
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Pair", systemImage: "gearshape") { showSettings = true }
                }
            }
            .safeAreaInset(edge: .bottom) { StatusBar(text: model.status) }
            .refreshable { await model.refreshSessions() }
            .sheet(isPresented: $showSettings) { SettingsView(model: model) }
            .task {
                while !Task.isCancelled {
                    await model.refreshSessions()
                    try? await Task.sleep(for: .seconds(4))
                }
            }
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

/// One line of feedback, always in the same place.
struct StatusBar: View {
    let text: String?

    var body: some View {
        if let text {
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.white.opacity(0.06))
        }
    }
}
