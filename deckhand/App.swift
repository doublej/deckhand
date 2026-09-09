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
                    live.begin { hex, kind in
                        try await model.settings.client()?.register(pushToken: hex, kind: kind)
                    }
                }
        }
    }
}

/// Portrait is one session at a time. Landscape is the whole deck at once.
struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width > geometry.size.height {
                DeckView(model: model)
            } else {
                SessionListView(model: model)
            }
        }
        .ignoresSafeArea(.keyboard)
    }
}
