import DeckhandKit
import PhotosUI
import SwiftUI

/// A glyph, and the word beside it where there is room for one. A deck column has room for two
/// glyphs and nothing else. Its own view because a picker's label is built outside the main
/// actor, which a method on the card cannot be.
struct Attach: View {
    let word: String
    let symbol: String
    let compact: Bool

    var body: some View {
        if compact {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
        } else {
            Label(word, systemImage: symbol)
        }
    }
}

/// The two ways a picture gets in, behind one word. Both are always offered: the clipboard one
/// was hidden whenever the clipboard held no image, which from the outside is a button that
/// comes and goes for no visible reason.
///
/// The picker is presented by the menu rather than being the label of one, because a
/// `PhotosPicker` is a control and not a menu item — putting one inside a `Menu` gives a row
/// that opens nothing. `.photosPicker(isPresented:)` is the same picker with the trigger
/// separated from it, which is what a menu needs.
///
/// As many photos as you like in one trip, numbered as they are chosen. One per trip was a
/// picker reopened four times to say one thing about four screenshots, and `.ordered` is what
/// makes the order they arrive in the order they were picked rather than the order the library
/// happens to hold them — which is the order the words about them end up in.
///
/// Its own view, and its own `@State`, because `picked` and `picking` were only ever this
/// menu's: they sat on the card, where every redraw of the prompt carried them.
struct PictureMenu: View {
    let attach: (Snap) -> Void
    var paste: (() -> Void)?
    let compact: Bool
    @State private var picked: [PhotosPickerItem] = []
    @State private var picking = false

    var body: some View {
    Menu {
                Button("Photos", systemImage: "photo.badge.plus") { picking = true }
                if let paste { Button("Clipboard", systemImage: "doc.on.clipboard", action: paste) }
            } label: {
                Attach(word: "Add attachments", symbol: "paperclip", compact: compact)
            }
            .accessibilityIdentifier("add-attachments")
            .photosPicker(isPresented: $picking,
                          selection: $picked,
                          maxSelectionCount: nil,
                          selectionBehavior: .ordered,
                          matching: .images,
                          photoLibrary: .shared())
            // The picker hands back items, not bytes; the bytes come over a moment later.
            // One at a time and in the order they were chosen, so each thumbnail appears as its
            // picture arrives rather than all of them after the slowest one.
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let bytes = try? await item.loadTransferable(type: Data.self),
                           let snap = Snap(picked: bytes) {
                            attach(snap)
                        }
                    }
                    picked = []
                }
            }
    }
}

    /// What is pinned, and the way into each one.
    ///
    /// A tap opens the picture to be marked up — the same marking a file gets. It used to take the
    /// picture off instead, and one tap cannot mean both: the two are as far apart as two meanings
    /// get, and the one that loses something was the one happening by accident. So taking a picture
    /// off lives inside the sheet the tap opens, where it is a full-sized button nobody reaches for
    /// while aiming at something else, and the 12pt cross that used to sit in the corner of a 48pt
    /// thumbnail — too small to hit on purpose, easy to hit by mistake — is gone with it.
///
/// Its own view because `ReviewCard` is at its line cap, and this belongs beside the menu that
/// puts the pictures there in the first place.
struct PinnedStrip: View {
    let snaps: [Snap]
    let compact: Bool
    let tap: (Snap) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xxs) {
                ForEach(snaps) { snap in
                    Image(uiImage: snap.picture)
                        .resizable()
                        .scaledToFill()
                        .frame(width: thumb, height: thumb)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture { tap(snap) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Mark up the attached picture")
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: thumb)
    }

    /// A thumbnail is a control, so it is the size a finger needs rather than the size a picture
    /// looks right at: 44pt even in a list row, where the strip used to be 34. The same raw
    /// number `ReviewActions` and `FilesView` write — no spacing token means "a finger".
    private var thumb: CGFloat { compact ? 44 : 56 }
}

/// The shape the card's two foot controls are drawn in: Add on the left, Edit on the right.
///
/// It exists because they were built separately and stopped matching. Add carries a capsule for
/// when it is recording, and a capsule needs padding inside it; Edit had none, so bottom-aligning
/// the two boxes put their *ink* four points apart — the padding under Add's word is inside its
/// box and the box is what got aligned. One set of insets used by both is the only version of
/// this that cannot drift.
///
/// Clear at rest for both. Add fills while it is listening, which is the one thing on the card
/// that has to be unmissable; a resting fill on either would read as a button you are meant to
/// press next, and neither is.
struct Chip: ViewModifier {
    let fill: Color

    /// Small enough that the capsule does not read as a button, wide enough that it does not cut
    /// into the glyph while it is filled.
    static let insets = EdgeInsets(top: Spacing.xxs, leading: Spacing.extraSmall,
                                   bottom: Spacing.xxs, trailing: Spacing.extraSmall)

    func body(content: Content) -> some View {
        content
            .padding(Self.insets)
            .background(Capsule().fill(fill))
    }
}

extension View {
    /// Draw this as one of the card's foot controls. See ``Chip``.
    func chip(_ fill: Color) -> some View { modifier(Chip(fill: fill)) }
}

/// A way into the words, at the foot of the staging box on the right: Alias, then Edit.
///
/// A glyph and a word with nothing behind them — the quietest controls on the card. Neither
/// sends nor throws away: Edit opens the words, Alias marks one of them for good. 44pt of
/// finger under 11pt of ink, the trade `SayRest` makes.
///
/// One type rather than two views, for ``Chip``'s own reason, written directly above: two
/// controls built separately stop matching, and these two sit four points apart where that is
/// unmissable.
struct WayIn: View {
    let word: String
    let symbol: String
    /// Only the last control in the row loses its trailing inset, so the row ends on the column
    /// the words above it end on — the mirror of what `SayRest` does on the leading side.
    var last = false
    let open: () -> Void
    @Environment(\.accent) private var accent

    /// The minimum a finger can be asked to hit. The same raw number `ReviewActions`, `SayRest`
    /// and `FilesView` write: no spacing token means "a finger".
    private static let touch: CGFloat = 44

    var body: some View {
        Button(action: open) {
            Label(word, systemImage: symbol)
                .font(Typography.hint)
                .foregroundStyle(accent)
                .lineLimit(1)
                .chip(.clear)
                .padding(.trailing, last ? -Chip.insets.trailing : 0)
                // Bottom of the box, for the reason `SayRest.face` gives: these sit on the card's
                // foot row and centred ink floats above the edge it belongs on.
                .frame(minHeight: Self.touch, alignment: .bottomTrailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
