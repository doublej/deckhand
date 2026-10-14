import DeckhandKit
import SwiftUI

/// Deckhand on the Mac: the manager one click away in the menu bar, the same conversation in a
/// window of its own, and a notification for every card the daemon raises for a session.
///
/// There was a menu bar app once and it was deleted the same day, because utt's page took over
/// every one of its buttons — starting, stopping and watching the daemon. This one does none of
/// that. It is the phone's manager panel and its Lock Screen, for the person at the Mac.
@main
struct DeckhandMacApp: App {
    @NSApplicationDelegateAdaptor private var app: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            ManagerPanel(desk: app.desk, place: .menu)
                .frame(width: 400, height: 560)
        } label: {
            MenuLabel(desk: app.desk)
        }
        .menuBarExtraStyle(.window)

        Window("Deckhand", id: ManagerPanel.window) {
            ManagerPanel(desk: app.desk, place: .window)
                .frame(minWidth: 380, minHeight: 420)
        }
        .defaultSize(width: 480, height: 680)
        // The rail surface runs to the top edge: a light title bar over it is two surfaces at once.
        .windowStyle(.hiddenTitleBar)
        // Opened from the menu, the Dock or a notification, never at launch: it starts at login.
        .defaultLaunchBehavior(.suppressed)
    }
}

/// Owns the desk, so the one loop starts once, at launch, and never with a view.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let desk = Desk()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await desk.run() }
    }

    /// Opening the app again while it runs — the Dock, Cmd-Tab, Spotlight, `open` — shows the
    /// window. A regular app on purpose, not `LSUIElement`: it gets its own Cmd-Tab entry.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        desk.showWindow?()
        AppActivation.front()
        return false
    }
}

/// The icon in the menu bar, and the one view that is alive for as long as the app is.
///
/// That is why it hands `openWindow` to the desk: a tapped notification arrives in no view at
/// all, and this is the only place an `OpenWindowAction` can be had from before any panel opens.
private struct MenuLabel: View {
    let desk: Desk
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: desk.working ? "ellipsis.bubble.fill" : "bubble.left.and.text.bubble.right")
            .task { desk.showWindow = { openWindow(id: ManagerPanel.window) } }
    }
}
