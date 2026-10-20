import DeckhandKit
import SwiftUI

/// Makes a `localhost` link a session wrote mean something on a phone.
///
/// The session is not wrong: `http://localhost:5173` is exactly true where it is running. It is
/// the phone that is somewhere else, running none of it. There is no way to be sure which
/// machine was meant, so the tap offers the ones it could have been — the Mac as it reports
/// itself, and the address this phone already reaches it on — rather than picking one and
/// opening something that is not there.
///
/// A path the session wrote is a file on the Mac, so it opens in the same viewer the files square
/// uses, fetched from the Mac — which serves it only if this session's transcript named it.
struct LocalLinks: ViewModifier {
    @Bindable var model: AppModel
    let session: Session
    @State private var choices: [URL] = []
    @State private var file: Asset?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction(handler: open))
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
            .sheet(item: $file) { AssetView(model: model, session: session, asset: $0) }
    }

    private func open(_ url: URL) -> OpenURLAction.Result {
        if let path = Links.macPath(of: url) {
            file = Asset(named: path)
            return .handled
        }
        guard Links.isLocal(url) else { return .systemAction }
        let elsewhere = Links.choices(for: url, mac: model.macAddress, paired: model.settings.host)
        // Nowhere else it could be: no question worth asking.
        guard elsewhere.count > 1 else { return .systemAction }
        choices = elsewhere
        return .handled
    }
}
