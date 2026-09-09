import DeckhandKit
import PencilKit
import SwiftUI

/// What has been marked on a picture and not yet turned into feedback.
///
/// Keyed by the file, not by the session, because that is what the marks are about —
/// `asset.path` is an `Asset`'s own id, so two screenshots marked in one sitting cannot bleed
/// into each other however often their sheets are opened and closed.
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
        guard let snap = Snap(flattened(markup, onto: picture), name: pngName(for: asset)) else {
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

    /// `.png` whatever the original was, because `Snap` PNG-encodes whatever picture it is handed
    /// and the Mac decides what a file is by its suffix alone — a `.jpeg` holding PNG bytes is
    /// the same bug as a wav named `.m4a`. The stem says which file this is a copy of, which only
    /// the upload's own filename and this phone's logs ever see: the Mac renames it to a
    /// timestamp on the way in, so what tells the session which picture the marks are about is
    /// `Pin.prose` naming the unmarked original.
    private func pngName(for asset: Asset) -> String {
        let stem = (asset.name as NSString).deletingPathExtension
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
