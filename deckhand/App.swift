import SwiftUI

@main
struct DeckhandApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
                .tint(.white)
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
