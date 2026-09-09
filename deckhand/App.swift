import SwiftUI

@main
struct DeckhandApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("deckhand")
                .font(.largeTitle)
            Text("iOS remote for live Claude Code sessions in iTerm — list, read, and speak to them")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
