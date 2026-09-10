import DeckhandKit
import Foundation

/// The three things the app does with an artifact: list them, fetch one, send back what the
/// person said. Together rather than split across `Reading.swift` and the controls, because an
/// artifact is one round trip with a person in the middle of it — the answer is the reason the
/// page was fetched at all.
@MainActor
extension AppModel {
    /// The slips this session has written for the phone. Asked for when the section is opened
    /// and again when the viewer closes, which is when `answered` can have changed. Not polled:
    /// it is a directory listing on the Mac and an agent writes one of these every few hours.
    func loadArtifacts(for session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            self.artifacts[session.sessionId] = try await client.artifacts(of: session.sessionId)
        }
    }

    /// One page's HTML. Never kept on the model: it is the one thing here the app does not
    /// trust, it is only ever wanted by the screen asking for it, and the screen hands it
    /// straight to `ArtifactPage.armoured`.
    func page(of artifact: Artifact, in session: Session) async throws -> String {
        guard let client = settings.client() else { throw DeckhandError.unauthorized }
        return try await client.page(of: artifact.id, in: session.sessionId)
    }

    /// What the person answered last time, as JSON text for the bridge — `"null"` where nobody has.
    ///
    /// Never throws, unlike the page it travels with. A page that cannot be fetched is a screen
    /// with nothing on it and has to say so; an answer that cannot be fetched is a page that draws
    /// itself empty, which is exactly what it did before it could read its own answer at all.
    func answered(to artifact: Artifact, in session: Session) async -> String {
        guard let client = settings.client() else { return "null" }
        return (try? await client.answered(artifact.id, in: session.sessionId)) ?? "null"
    }

    /// What the person answered, on its way to the Mac. Throws rather than reporting into
    /// `status`, because the viewer covers the screen the status line lives on and has to say
    /// this itself.
    func answer(
        _ artifact: Artifact,
        in session: Session,
        valueJSON: String
    ) async throws -> Delivery {
        guard let client = settings.client() else { throw DeckhandError.unauthorized }
        return try await client.answer(artifact.id,
                                      in: session.sessionId,
                                      valueJSON: valueJSON,
                                      route: preferences.route)
    }
}
