import SwiftUI

@main
struct DeckhandApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SessionListView(model: model)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}
