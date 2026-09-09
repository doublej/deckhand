import DeckhandKit
import PhotosUI
import SwiftUI

/// What was heard, held until you say so. Borrowed from utt's own review HUD: the transcript,
/// where it is going, and the two things you can do about it. utt offers ⏎ and ⎋ because a
/// panel that never takes focus makes the keys the real interface; a phone has no keys, so
/// the buttons are the whole affordance.
struct ReviewCard: View {
    let text: String
    let target: String
    /// Takes the words as they stand when Send is pressed, which is not always the words that
    /// were heard: what utt returns is a first draft, and the point of holding it is to fix it.
    let send: (String) -> Void
    let discard: () -> Void
    /// What the chain on the Mac did to these words on the way here, and what it will do to them
    /// if they are sent as they stand. One value rather than two strings, because they come off
    /// one response and a card showing one without the other would be the bug either way.
    ///
    /// The card shows the prepared words, because those are what the session will be handed — and
    /// a word differing silently from the one that was spoken is a card lying about the thing it
    /// exists to confirm. These two lines are how it does not. Send stays pressable even when the
    /// chain will refuse: a greyed-out button with no sentence beside it leaves somebody holding
    /// words with no way to find out why, which is the worse half of this problem.
    var filtered: Filtered?
    /// Small enough for a deck column, which has no room for a full card.
    var compact = false
    /// What is already pinned to these words, and the two ways to pin another. Left out where
    /// there is nobody to hand a picture to.
    var snaps: [Snap] = []
    var attach: ((Snap) -> Void)?
    var paste: (() -> Void)?
    /// A pinned picture is to be marked up, and the words as they stand on screen. The sheet belongs
    /// to whoever presented the card, because it needs the model and the session and this view has
    /// deliberately never held either — see `SnapView`.
    ///
    /// The words travel with the tap for the reason `SayMore` sends them with a clip: an edit made
    /// by hand lives in this card until Send, the remarks are laid *under* the words, and under the
    /// corrected ones is the only place they can honestly go.
    var mark: ((Snap, String) -> Void)?
    /// What it takes to say the rest of it, or nil where there is no recorder to lend — a deck
    /// column, which has no room for another control either. See `SayMore`.
    var more: SayMore?
    /// What it takes to say something into the editor, which is not the same move as `more`: that
    /// one hands another clip to the Mac and lays the words under what the card holds, chain notes
    /// and all; this one fills in a box on a sheet. Nil wherever `more` is, and for the same reason.
    var say: Dictation?
    @State private var picked: [PhotosPickerItem] = []
    @State private var editing = false
    @Environment(\.accent) private var accent
    /// The words as they stand. Seeded from what was heard and kept across an edit, so opening
    /// the editor twice does not throw away the first correction.
    @State private var draft: String?

    private var words: String { draft ?? text }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            attachments
            // All of it. This was capped at six lines, which quietly hid the end of anything
            // said in more than a sentence — and the end of a spoken instruction is usually
            // the part with the actual instruction in it. Long ones scroll rather than clip.
            ScrollView {
                Text(words)
                    .font(compact ? .system(size: 10) : Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: compact ? 96 : 260)
            .scrollBounceBehavior(.basedOnSize)
            // Under the words, quiet, and in a deck column too: there is no size of card on which
            // it is acceptable to show somebody a word they did not say without saying so.
            if let note = filtered?.note { aside(note, in: Palette.textTertiary) }
            // The colour is the whole of the difference, as everywhere else in this app: the words
            // alone in the state's own colour, never a label inside a capsule that reads as
            // something you press — and there is a real button an inch below this one.
            if let refusal = filtered?.refusal { aside(refusal, in: Palette.lcdRed) }
            if !snaps.isEmpty { pinned }
            ReviewActions(route: target,
                          words: words,
                          discard: discard,
                          edit: { editing = true },
                          send: send,
                          more: more,
                          finished: { draft = nil },
                          compact: compact)
        }
        .sheet(isPresented: $editing) {
            Editor(words: words, target: target, say: say) { edited in
                draft = edited
                editing = false
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? Spacing.extraSmall : Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
        )
    }

    /// A line under the words, quiet, and in a deck column too: there is no size of card on which
    /// it is acceptable to show somebody a word they did not say without saying so.
    private func aside(_ words: String, in colour: Color) -> some View {
        Text(words)
            .font(Typography.hint)
            .foregroundStyle(colour)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The two ways a picture gets in, above the words they will go with. Both are always
    /// offered: the clipboard one was hidden whenever the clipboard held no image, which from
    /// the outside is a button that comes and goes for no visible reason.
    ///
    /// As many photos as you like in one trip, numbered as they are chosen. One per trip was a
    /// picker reopened four times to say one thing about four screenshots, and `.ordered` is what
    /// makes the order they arrive in the order they were picked rather than the order the library
    /// happens to hold them — which is the order the words about them end up in.
    @ViewBuilder private var attachments: some View {
        if let attach {
            HStack(spacing: Spacing.small) {
                PhotosPicker(selection: $picked,
                             maxSelectionCount: nil,
                             selectionBehavior: .ordered,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Attach(word: "Photos", symbol: "photo.badge.plus", compact: compact)
                }
                if let paste {
                    Button(action: paste) {
                        Attach(word: "Clipboard", symbol: "doc.on.clipboard", compact: compact)
                    }
                        .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .font(Typography.hint)
            .foregroundStyle(accent)
            // The picker hands back items, not bytes; the bytes come over a moment later.
            // One at a time and in the order they were chosen, so each thumbnail appears as its
            // picture arrives rather than all of them after the slowest one.
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let bytes = try? await item.loadTransferable(type: Data.self),
                           let snap = Snap(bytes: bytes, name: "photo.\(suffix(of: bytes))") {
                            attach(snap)
                        }
                    }
                    picked = []
                }
            }
        }
    }

    /// What a photo library hands over can be anything; the Mac decides by suffix, so the
    /// suffix has to match the bytes rather than the guess.
    private func suffix(of bytes: Data) -> String {
        let head = bytes.prefix(4)
        if head.starts(with: [0x89, 0x50]) { return "png" }
        if head.starts(with: [0xFF, 0xD8]) { return "jpg" }
        return "heic"
    }

    /// What is pinned, and the way into each one.
    ///
    /// A tap opens the picture to be marked up — the same marking a file gets. It used to take the
    /// picture off instead, and one tap cannot mean both: the two are as far apart as two meanings
    /// get, and the one that loses something was the one happening by accident. So taking a picture
    /// off lives inside the sheet the tap opens, where it is a full-sized button nobody reaches for
    /// while aiming at something else, and the 12pt cross that used to sit in the corner of a 48pt
    /// thumbnail — too small to hit on purpose, easy to hit by mistake — is gone with it.
    private var pinned: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xxs) {
                ForEach(snaps) { snap in
                    Image(uiImage: snap.picture)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.thumb(compact), height: Self.thumb(compact))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            mark?(snap, words)
                            // Handed over, so the card reads them out of the model from here on —
                            // which is where the remarks about this picture are about to land.
                            draft = nil
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Mark up the attached picture")
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: Self.thumb(compact))
    }

    /// A thumbnail is a control now, so it is the size a finger needs rather than the size a
    /// picture looks right at: 44pt even in a list row, where the strip used to be 34. The same
    /// raw number `ReviewActions` and `FilesView` write, for the same reason — no spacing token
    /// means "a finger".
    private static func thumb(_ compact: Bool) -> CGFloat { compact ? 44 : 56 }
}

/// A glyph, and the word beside it where there is room for one. A deck column has room for two
/// glyphs and nothing else. Its own view because a picker's label is built outside the main
/// actor, which a method on the card cannot be.
private struct Attach: View {
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

/// The whole screen above the keyboard, as one field holding what was heard.
///
/// A phone dictates better than it types, but not perfectly: utt hears a name wrong, or the
/// sentence ran on, and the fix is two words. The card is far too small a place to make that
/// fix — so the edit is a page of its own, opened focused with the keyboard already up, which
/// is the only arrangement where correcting one word is faster than saying the whole thing again.
///
/// And the mark is here too, under the field, because this is the page you reach *because* a word
/// came back wrong: half of what happens here is a correction typed, and the other half is another
/// sentence that is easier said. It lands under what is in the box and never over it.
private struct Editor: View {
    let words: String
    let target: String
    var say: Dictation?
    let keep: (String) -> Void
    @State private var edited: String = ""
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $edited)
                .font(Typography.mono)
                .focused($typing)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Spacing.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.surfaceGround)
                // Above the keyboard rather than in the toolbar: a 44pt capsule does not fit in a
                // navigation bar beside Cancel and Done, and this is the one control here your
                // thumb is already resting on. A blank line between the halves, because two things
                // said one after the other are two paragraphs and not one long sentence.
                .safeAreaInset(edge: .bottom) {
                    if let say {
                        SayInto(say: say, text: $edited, gap: "\n\n")
                            .padding(.horizontal, Spacing.medium)
                            .padding(.bottom, Spacing.extraSmall)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .navigationTitle("→ \(target)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.tint(Palette.textSecondary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { keep(edited) }.tint(Palette.tint).fontWeight(.semibold)
                    }
                }
        }
        .task {
            edited = words
            // A beat, or the field takes focus before it is on screen and the keyboard does
            // not come up at all — which leaves a page that looks editable and is not.
            try? await Task.sleep(for: .milliseconds(120))
            typing = true
        }
    }
}
