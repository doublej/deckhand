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

    /// The marked copy in the unmarked one's place, and — unless it is a copy of a copy — the
    /// original kept right behind it.
    ///
    /// Both, because a marker sits on top of the thing it is about. At a twentieth of the shorter
    /// side it covers a control, a word, a face, and that is very often exactly what the remark
    /// beside it is about. A file's original stays on the Mac and `Pin.prose` names its path; an
    /// attachment has no original anywhere else — it is bytes on this phone until Send — so
    /// sending it is the only way there is one.
    ///
    /// In that place rather than on the end because the pictures reach the session in the order
    /// they were attached, and the remarks about them were laid into the card in that same order.
    ///
    /// False when that picture is not attached any more, which is the one case where the remarks
    /// must not be written at all. See `feedback(_:of:in:)`.
    func pair(_ copy: Snap, over snap: Snap, keepingOriginal: Bool, in session: Session) -> Bool {
        guard let spot = attached[session.sessionId]?.firstIndex(where: { $0.id == snap.id }) else {
            return false
        }
        attached[session.sessionId]?.replaceSubrange(spot...spot,
                                                     with: keepingOriginal ? [copy, snap] : [copy])
        return true
    }

    /// Sends the words, with anything pinned to them.
    ///
    /// The pictures go first and the words name where they landed, so a failed upload means
    /// nothing was said — better than a message pointing at a file the Mac does not have.
    func send(_ text: String, to session: Session) async {
        guard let client = settings.client() else { return }
        let pinned = snaps(for: session)
        hold(nil, for: session)
        status = pinned.isEmpty ? "Sending to \(session.name)…" : "Sending the pictures first…"
        await run {
            let paths = try await self.keep(pinned, for: session, with: client)
            // Always prepared: every caller of this is a review card, so these words have been
            // on screen and the chain has already had its turn at them.
            let sent = try await client.say(text,
                                            to: session.sessionId,
                                            route: self.preferences.route,
                                            images: paths,
                                            prepared: true)
            guard self.went(sent, saying: text, to: session) else { return }
            await self.loadTurns(for: session)
        }
    }

    /// What became of the words, and what the screen does about it. True only when they are
    /// actually in the session, which is the one case where the transcript is worth re-reading.
    ///
    /// A filter refusing them and a session that would not take them are the same case here:
    /// either way the words still exist and have been said to nobody, so they go back into the
    /// card rather than being reported and let go of. The status line says which of the two.
    private func went(_ sent: Delivery, saying text: String, to session: Session) -> Bool {
        guard sent.went else {
            hold(text,
                 for: session,
                 notes: sent.notes,
                 stoppedBy: sent.stoppedBy,
                 because: sent.deliveryError)
            status = sent.stoppedBy
                .map { stopped(by: $0, because: sent.deliveryError, notes: sent.notes) }
                ?? sent.deliveryError
                ?? "\(session.name) did not take it"
            return false
        }
        attached[session.sessionId] = nil
        status = said("Sent to \(session.name) by \(sent.deliveredBy ?? "the Mac")",
                      notes: sent.notes)
        return true
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
