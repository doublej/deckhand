import SwiftUI

@main
struct DeckhandMenuApp: App {
    @State private var monitor = Monitor()

    var body: some Scene {
        // A filled hull when the daemon answers, an empty one when it does not: the only
        // piece of state readable without opening the menu.
        MenuBarExtra("Deckhand", systemImage: monitor.isUp ? "sailboat.fill" : "sailboat") {
            MenuView(monitor: monitor)
        }
        // The window style, not the plain menu: a menu cannot carry a monospaced table,
        // and `.task` only runs for as long as this window is on screen.
        .menuBarExtraStyle(.window)
    }
}

/// Three status rows, the actions, and the one line every action reports into.
private struct MenuView: View {
    let monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            status
            Divider()
            ForEach(Action.all) { action in
                button(action.title) { monitor.perform(action) }
            }
            button("Quit") { NSApp.terminate(nil) }
            Divider()
            Text(monitor.result)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(.body, design: .monospaced))
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .task { await monitor.poll() }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(monitor.rows, id: \.self) { Text($0) }
        }
    }

    private func button(_ title: String, _ act: @escaping () -> Void) -> some View {
        Button(title, action: act)
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
