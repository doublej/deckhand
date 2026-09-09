import DeckhandKit
import SwiftUI

/// Pictures pinned to words that have not been sent yet.
///
/// They belong to the review card and nowhere else: the phone has no way to speak a screenshot,
/// so an image is something you add to what was heard, in the one moment between hearing it and
/// sending it. Held on the phone until then — the Mac only gets them if the words are sent.
struct Snap: Identifiable, Equatable {
    let id = UUID()
    /// For the thumbnail. Drawn once here rather than decoded on every layout pass.
    let picture: UIImage
    let bytes: Data
    /// What the Mac will call it. The suffix is the whole of what it checks.
    let name: String

    /// PNG, because that is lossless and what a screenshot already is. A photo out of the
    /// library arrives as its own data and keeps it.
    init?(_ picture: UIImage, name: String = "snap.png") {
        guard let bytes = picture.pngData() else { return nil }
        self.picture = picture
        self.bytes = bytes
        self.name = name
    }

    init?(bytes: Data, name: String) {
        guard let picture = UIImage(data: bytes) else { return nil }
        self.picture = picture
        self.bytes = bytes
        self.name = name
    }
}

@MainActor
extension AppModel {
    /// What is pinned to the words waiting to be sent to this session.
    func snaps(for session: Session) -> [Snap] {
        attached[session.sessionId] ?? []
    }

    func attach(_ snap: Snap, to session: Session) {
        attached[session.sessionId, default: []].append(snap)
        status = "Picture attached"
    }

    /// Whatever picture is on the clipboard. Nothing happens if it holds no image — the button
    /// that calls this is only offered when it does.
    func attachFromClipboard(to session: Session) {
        guard let picture = UIPasteboard.general.image, let snap = Snap(picture) else {
            status = "Nothing on the clipboard to attach"
            return
        }
        attach(snap, to: session)
    }

    func unattach(_ snap: Snap, from session: Session) {
        attached[session.sessionId]?.removeAll { $0.id == snap.id }
    }

    /// Sends the words, with anything pinned to them.
    ///
    /// The pictures go first and the words name where they landed, so a failed upload means
    /// nothing was said — better than a message pointing at a file the Mac does not have.
    func send(_ text: String, to session: Session) async {
        guard let client = settings.client() else { return }
        let pinned = snaps(for: session)
        review[session.sessionId] = nil
        status = pinned.isEmpty ? "Sending to \(session.name)…" : "Sending the pictures first…"
        await run {
            let paths = try await self.keep(pinned, for: session, with: client)
            let sent = try await client.say(text,
                                            to: session.sessionId,
                                            route: self.preferences.route,
                                            images: paths)
            guard sent.delivered else {
                self.review[session.sessionId] = text
                self.status = sent.deliveryError ?? "\(session.name) did not take it"
                return
            }
            self.attached[session.sessionId] = nil
            self.status = "Sent to \(session.name) by \(sent.deliveredBy ?? "the Mac")"
            await self.loadTurns(for: session)
        }
    }

    private func keep(
        _ pinned: [Snap],
        for session: Session,
        with client: DeckhandClient
    ) async throws -> [String] {
        var paths: [String] = []
        for snap in pinned {
            paths.append(try await client.upload(image: snap.bytes,
                                                 named: snap.name,
                                                 to: session.sessionId))
        }
        return paths
    }
}
