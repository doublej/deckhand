import DeckhandKit
import PencilKit
import SwiftUI

/// What has been marked on a picture and not yet turned into feedback.
///
/// Keyed by the picture, not by the session, because that is what the marks are about. A file on
/// the Mac is keyed by `asset.path`, which is an `Asset`'s own id; a picture pinned to the review
/// card has no path, so it is keyed by its `Snap`'s id under a `snap:` prefix. Two screenshots, or
/// two photos picked in the same trip through the library, therefore cannot bleed into each other
/// however often their sheets are opened and closed — even when the bytes are identical, because a
/// `Snap` is a fresh id per attachment and not a hash of what is in it. The prefix is what keeps
/// the two kinds apart: a path starts with a slash and can never be spelled like a `snap:` key.
///
/// A global rather than a field on `AppModel` because a Swift extension cannot add a stored
/// property, and this is the only thing in the app that reads it. `@MainActor` makes it exactly
/// as safe as the model: every door into it below is a main-actor method.
///
/// In memory only, and never pruned, which is deliberate rather than forgotten. It has the same
/// lifetime as the review card it feeds — `review` and `attached` are in memory too — so
/// backgrounding the app keeps all three, killing it loses all three, and a session dropping off
/// the listing takes none of them. One entry costs a drawing and a few lines of text; what ends
/// one is sending the feedback or discarding it, and both of those go through this file.
@MainActor private var marked: [String: Markup] = [:]

@MainActor
extension AppModel {
    /// What is already on this picture, so reopening the sheet finds the pins where they were.
    func markup(of asset: Asset) -> Markup {
        marked[asset.path] ?? Markup(pins: [], drawing: PKDrawing())
    }

    /// Held while the sheet is closed.
    ///
    /// An emptied one is forgotten rather than stored: undoing every mark and closing leaves
    /// nothing to come back to, and a kept-but-blank entry would be indistinguishable from a
    /// real markup everywhere else in this file.
    func keep(_ markup: Markup, of asset: Asset) {
        marked[asset.path] = markup.isEmpty ? nil : markup
    }

    /// Flattens it, pins it to the review card with the numbered comments, forgets the markup.
    ///
    /// Nothing is sent from here. The card is where words wait to be read, and the whole point
    /// of landing feedback in it is that you can still dictate more, edit it, and then press the
    /// Send that was already there — the one that uploads the pictures first and names where
    /// they landed, so none of this needed anything new on the Mac.
    func feedback(_ markup: Markup, of asset: Asset, picture: UIImage, in session: Session) {
        // A picture with nothing on it is not feedback. The sheet's own Done button will not
        // offer itself for an empty markup either; this is the shared path, so it says no too.
        guard !markup.isEmpty else { return }
        guard let snap = Snap(flattened(markup, onto: picture),
                             name: pngName(marking: asset.name)) else {
            status = "Could not draw the marked copy of \(asset.name)"
            return
        }
        // Underneath whatever was already said, never instead of it — `Appending.swift`, which
        // is the one path that adds to a card rather than replacing what is in it. `Pin.prose`
        // opens with a heading of its own, so the two read as two paragraphs.
        append(Pin.prose(markup.pins, about: asset.name, at: asset.path), to: session)
        attach(snap, to: session)
        marked[asset.path] = nil
        status = landed(markup.pins.count, on: asset.name)
    }

    func forget(markupOf asset: Asset) {
        marked[asset.path] = nil
    }

    /// What is already on a picture pinned to the review card, same as for a file.
    func markup(of snap: Snap) -> Markup {
        marked[key(of: snap)] ?? Markup(pins: [], drawing: PKDrawing())
    }

    func keep(_ markup: Markup, of snap: Snap) {
        marked[key(of: snap)] = markup.isEmpty ? nil : markup
    }

    func forget(markupOf snap: Snap) {
        marked[key(of: snap)] = nil
    }

    /// Flattens it, puts the marked copy in the unmarked one's place, and lays the numbered
    /// remarks under whatever the card is already holding.
    ///
    /// In its place rather than beside it, which is the one way this differs from a file. A file's
    /// unmarked original stays on the Mac and `Pin.prose` names it, so the marked copy is a second
    /// picture worth having. An attachment has no original anywhere else — it is bytes on this
    /// phone until Send — so keeping both would upload two pictures a session cannot tell apart,
    /// with no path available to say which of them the remarks are about. The marks are in the
    /// picture from here on, exactly as they are once a file's feedback has been handed over.
    func feedback(_ markup: Markup, of snap: Snap, in session: Session) {
        guard !markup.isEmpty else { return }
        guard let copy = Snap(flattened(markup, onto: snap.picture),
                              name: pngName(marking: snap.name)) else {
            status = "Could not draw the marked copy of the picture"
            return
        }
        // The picture first, the words second. Remarks about an attachment that is no longer
        // attached are the one lie this order rules out.
        guard replace(snap, with: copy, in: session) else {
            status = "That picture is no longer attached"
            return
        }
        append(Pin.prose(markup.pins), to: session)
        forget(markupOf: snap)
        status = landed(markup.pins.count, on: "the picture")
    }

    /// A `Snap`'s own id, prefixed, which is also what `unattach` and the thumbnail strip identify
    /// it by. Not its name — every photo out of the library is called `photo.jpg` — and not its
    /// bytes, which would make the same picture attached twice one markup shared between them.
    private func key(of snap: Snap) -> String { "snap:\(snap.id)" }

    /// `.png` whatever the original was, because `Snap` PNG-encodes whatever picture it is handed
    /// and the Mac decides what a file is by its suffix alone — a `.jpeg` holding PNG bytes is
    /// the same bug as a wav named `.m4a`. The stem says which file this is a copy of, which only
    /// the upload's own filename and this phone's logs ever see: the Mac renames it to a
    /// timestamp on the way in, so what tells the session which picture the marks are about is
    /// `Pin.prose` naming the unmarked original, or — for an attachment, which has no original to
    /// name — the markers burnt into the only copy there is.
    private func pngName(marking name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        return "\(stem.isEmpty ? "picture" : stem)-marked.png"
    }

    /// What the status line says, which is how this app tells you anything happened at all. The
    /// count is the useful half: it is the one number saying the marks you made are the marks
    /// that arrived.
    private func landed(_ pins: Int, on name: String) -> String {
        guard pins > 0 else {
            return "Your drawing on \(name) is in the card — read it, then send"
        }
        return "\(pins == 1 ? "1 mark" : "\(pins) marks") on \(name) — read it, then send"
    }
}
