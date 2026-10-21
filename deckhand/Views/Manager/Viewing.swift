import DeckhandKit
import SwiftUI

/// What a session's page owes the drawer and the links: saying which session is under the
/// drawer, and opening the one slip a link named.
///
/// A modifier on `SessionView` rather than more of it, which sits at its length gate.
struct Viewing: ViewModifier {
    @Bindable var model: AppModel
    let session: Session
    /// The page's own recorder, lent to the slip as `WaitingSlip` lends its own.
    let say: Dictation
    @State private var slip: Artifact?

    func body(content: Content) -> some View {
        content
            // The manager hears this session as "this one", and the rail's swipe stands down.
            .onAppear { model.manager.viewing = session.sessionId }
            // Only if it is still this one: a session pushed over this page arrives before this
            // one leaves, and clearing it then would forget the page that is actually up.
            .onDisappear {
                if model.manager.viewing == session.sessionId { model.manager.viewing = nil }
            }
            // On the way in as well as on a change: a link sets it before this page exists.
            .task { await open(model.manager.slip) }
            .onChange(of: model.manager.slip) { _, linked in Task { await open(linked) } }
            // A cover, for the reason `WaitingSlip` gives: the viewer is meant to have no chrome.
            .fullScreenCover(item: $slip) {
                ArtifactView(model: model, session: session, artifact: $0, say: say)
            }
    }

    /// The slip from a fresh listing — it may have been written a second ago. One that is gone
    /// opens the slips square instead, which says what there is.
    private func open(_ linked: LinkedSlip?) async {
        guard let linked, linked.session == session.sessionId else { return }
        model.manager.slip = nil
        await model.loadArtifacts(for: session)
        if let found = model.artifacts[session.sessionId]?.first(where: { $0.id == linked.id }) {
            slip = found
        } else {
            model.manager.pane = "slips"
        }
    }
}
