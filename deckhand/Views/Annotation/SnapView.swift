import DeckhandKit
import SwiftUI

/// Which picture is being marked, and whose words it is pinned to.
///
/// One value because the sheet needs both and the rail can be holding a card for more than one
/// session at a time, so the picture alone does not say where its remarks are meant to land.
struct Pinned: Identifiable {
    let snap: Snap
    let session: Session

    var id: UUID { snap.id }
}

/// A picture pinned to the review card, open to be marked up.
///
/// The same surface a file gets — tap a place, say what is wrong there, as many places on one
/// picture as it takes — for a picture the Mac has never seen. `AssetView` is the other caller of
/// `Marking`; this one has no download, no three kinds of file and no path, so the picture is in
/// hand from the first frame and all this view is is the toolbar around it.
///
/// A sheet, so `Palette.tint` throughout rather than the page's accent: the mark you hold to talk
/// is behind this, and only the page you are dictating into turns orange.
struct SnapView: View {
    let model: AppModel
    let session: Session
    let snap: Snap
    /// The marks, seeded from whatever was marked last time and kept when the sheet closes.
    @State private var markup = Markup()
    @State private var pencilling = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Marking(picture: snap.picture, markup: $markup, pencilling: pencilling)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surfaceGround)
                // What this phone calls the file is `photo.jpg`, and the Mac renames it to a
                // timestamp on the way in, so naming it here would name something nobody else
                // ever sees.
                .navigationTitle("Attached picture")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { remove }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        pencil
                        if !markup.isEmpty { hand }
                        Button("Close") { dismiss() }.tint(Palette.tint)
                    }
                }
        }
        // Kept until handed over or thrown away: the same picture opened again comes back with its
        // pins on it, which is the difference between marking one up and starting over.
        .task { markup = model.markup(of: snap) }
        .onDisappear { keep() }
    }

    /// The one way to lose an attachment now that a tap on the thumbnail opens this instead. It is
    /// behind that tap, at the far end of the bar from Send and Close, which is the same answer
    /// `ReviewActions` gives to pressing the wrong one: distance, not a confirmation.
    private var remove: some View {
        Button("Remove", role: .destructive) {
            model.forget(markupOf: snap)
            model.unattach(snap, from: session)
            // Nothing left to write back on the way out — see `keep()`.
            markup = Markup()
            dismiss()
        }
    }

    /// Parity with a file, and for the same reason: a single point cannot say "this whole row", so
    /// a circle or an arrow has to be drawable over the top.
    private var pencil: some View {
        Button {
            pencilling.toggle()
        } label: {
            Image(systemName: pencilling ? "pencil.tip.crop.circle.fill"
                                         : "pencil.tip.crop.circle")
        }
        .tint(pencilling ? Palette.tint : Palette.textSecondary)
        .accessibilityLabel("Draw on the picture")
    }

    /// The same word and the same button a file's feedback is handed over with, because it is the
    /// same gesture: the marks become words in the card, and the card's own Send is what sends.
    private var hand: some View {
        Button("Send") {
            model.feedback(markup, of: snap, in: session)
            // The marks are the card's now, burnt into the copy that took this picture's place.
            markup = Markup()
            dismiss()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .tint(Palette.tint)
    }

    /// What survives the sheet closing. An emptied markup is forgotten rather than kept, or
    /// deleting the last pin and closing would bring the first one back on the next open — which
    /// is also what makes handing over and removing need no flag of their own: both leave the
    /// markup empty, so both come through here as a forget.
    private func keep() {
        if markup.isEmpty {
            model.forget(markupOf: snap)
        } else {
            model.keep(markup, of: snap)
        }
    }
}
