import DeckhandKit
import SwiftUI

@main
struct DeckhandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @State private var live = LiveUpdates()

    var body: some Scene {
        WindowGroup {
            // No forced scheme: the rail paints its own dark ground, and a session page is
            // meant to be the phone's own light one. Forcing dark made both the same surface.
            RootView(model: model)
                .tint(Palette.tint)
                // The Mac drives the Lock Screen card, not the app: a backgrounded app has no
                // promise of running again soon. All this does is keep the Mac supplied with
                // the tokens that let it, for as long as the app is alive.
                .task {
                    // The archive's own tidying, done on the way in rather than on a timer: being
                    // opened is the only moment a phone app reliably gets, and the index is small
                    // enough that reading it costs nothing. It only ever drops clips that were
                    // actually said — see `ClipArchive.sweep`.
                    model.archive.sweep()
                    live.begin { hex, kind in
                        try await model.settings.client()?.register(pushToken: hex, kind: kind)
                    }
                }
        }
    }
}

/// Portrait is one session at a time. Landscape is the whole deck at once — and one swipe left
/// of either is the manager.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        // Outside the keyboard rule below, deliberately. The rail and the deck ignore the
        // keyboard because nothing on them is typed into; the manager panel is one long field
        // and has to rise for it, which it cannot do inside an ancestor that ignores it.
        ManagerShell(model: model) {
            GeometryReader { geometry in
                if geometry.size.width > geometry.size.height {
                    DeckView(model: model)
                } else {
                    SessionListView(model: model)
                }
            }
            .ignoresSafeArea(.keyboard)
        }
        // Set once, at the root, so every surface that renders markdown draws a mermaid fence
        // rather than printing it: a transcript, a briefing, a report a session left behind. The
        // seam is here because drawing one needs a web view and `Markdown` lives in DeckhandKit,
        // which has no UIKit in it on purpose.
        .diagrams { AnyView(MermaidBlock(source: $0)) }
    }
}
