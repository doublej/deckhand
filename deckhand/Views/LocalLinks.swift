import DeckhandKit
import SwiftUI

/// Makes a `localhost` link a session wrote mean something on a phone.
///
/// The session is not wrong: `http://localhost:5173` is exactly true where it is running. It is
/// the phone that is somewhere else, running none of it. There is no way to be sure which
/// machine was meant, so the tap offers the ones it could have been — the Mac as it reports
/// itself, and the address this phone already reaches it on — rather than picking one and
/// opening something that is not there.
struct LocalLinks: ViewModifier {
    /// The Mac's own address on the network, from `/health`. Absent until the first listing.
    let mac: String?
    /// Whatever was typed in Settings to reach the Mac. Proven to work, by definition.
    let paired: String
    @State private var choices: [URL] = []

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard Links.isLocal(url) else { return .systemAction }
                let elsewhere = Links.choices(for: url, mac: mac, paired: paired)
                // Nowhere else it could be: no question worth asking.
                guard elsewhere.count > 1 else { return .systemAction }
                choices = elsewhere
                return .handled
            })
            .confirmationDialog("Open where?", isPresented: .init(
                get: { !choices.isEmpty }, set: { if !$0 { choices = [] } }
            ), titleVisibility: .visible) {
                ForEach(choices, id: \.self) { url in
                    // Opened past the environment above, which would only ask the same question.
                    Button(url.absoluteString) { UIApplication.shared.open(url) }
                }
                Button("Cancel", role: .cancel) { choices = [] }
            } message: {
                Text("The session wrote this address for the Mac it is running on.")
            }
    }
}
