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
    /// What this clip cost from the press to these words being here, one quiet line *under* the
    /// row you press. Nil where the words came from somewhere other than a clip, and in a deck
    /// column, which has room for the words and the buttons and nothing else.
    var cost: ClipTiming?
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
    /// The names this session answers to, fetched when the picker opens. Nil where there is
    /// nobody to ask — a deck column, or a card built from words with no session behind them.
    var commands: (() async -> [SlashCommand])?
    @State private var picked: [PhotosPickerItem] = []
    @State private var picking = false
    @State private var editing = false
    @State private var choosing = false
    @Environment(\.accent) private var accent
    /// The words as they stand. Seeded from what was heard and kept across an edit, so opening
    /// the editor twice does not throw away the first correction.
    @State private var draft: String?

    private var words: String { draft ?? text }

    /// The card, the row you press, and the receipt — three things stacked, not one box holding
    /// all three.
    ///
    /// The buttons used to be the last row *inside* the container. They are outside it now, and
    /// that is the answer to a corner clash rather than a taste: a 44pt control is a 22pt corner,
    /// the card's was 12, and nesting the wider curve inside the tighter one is what read as
    /// wrong. `ReviewActions.face` tightened the button to match and left a row of small hard
    /// rectangles at the foot of a soft card. Taking the row out of the box removes the nesting
    /// instead of arguing about the radii: outside, nothing is concentric with anything, the
    /// buttons are capsules the way iOS makes 44pt controls, and the card is free to be as round
    /// as it likes. Which it now is — `Radius.extraLarge`, not `medium`.
    ///
    /// The container is also honest about what it holds now: the prompt and the things that make
    /// more of it. Everything you do *with* a finished prompt happens below the box it is in.
    ///
    /// A deck column keeps all of it inside, because 240 points has no room for a row of capsules
    /// standing on their own.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            staging
            if !compact {
                actions
                // Under the row you press, and still the only thing that may be: it is a receipt
                // rather than a fourth verb, so nothing below Send is both pressable and
                // consequential. Its stages open onto a slab of their own — see `ClipCost`.
                if let cost { ClipCost(timing: cost) }
            }
        }
        .sheet(isPresented: $editing) {
            Editor(words: words, target: target, say: say) { edited in
                draft = edited
                editing = false
            }
        }
        .sheet(isPresented: $choosing) {
            if let commands {
                // Into the draft, not out of the card: the whole point is that the words are
                // still yours to change afterwards, and what you said is still under it.
                CommandPicker(load: commands) { draft = $0.infront(of: words) }
            }
        }
    }

    private var actions: some View {
        ReviewActions(route: target,
                      words: words,
                      discard: discard,
                      edit: { editing = true },
                      send: send,
                      compact: compact)
    }

    /// The prompt itself and everything that adds to it, in the bordered box.
    private var staging: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            attachments
            // The words and the way to say more of them, tight together: the second lands on the
            // line under the first, so the control belongs where the caret would be.
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                // All of it. This was capped at six lines, which quietly hid the end of anything
                // said in more than a sentence — and the end of a spoken instruction is usually
                // the part with the actual instruction in it. Long ones scroll rather than clip.
                //
                // And it hugs them, up to that cap. The scroll box was the only greedy child in
                // this card, so on a short prompt it took every point the card was offered and
                // the slack fell between the sentence and the control that continues it.
                ScrollView {
                    Text(words)
                        .font(compact ? .system(size: 10) : Typography.mono)
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: compact ? 96 : 260)
                .fixedSize(horizontal: false, vertical: true)
                .scrollBounceBehavior(.basedOnSize)
                // It stood in the row at the foot until it read as a fourth thing you do *with*
                // the prompt rather than the one thing that makes more of it.
                if let more { SayRest(more: more, words: words) { draft = nil } }
            }
            // Under the words, quiet, and in a deck column too: there is no size of card on which
            // it is acceptable to show somebody a word they did not say without saying so.
            if let note = filtered?.note { aside(note, in: Palette.textTertiary) }
            // What the note cannot say: the sentence those words replaced. Without it a swap
            // that was wrong reads as a mishearing, and a mishearing as a swap.
            if let filtered, !compact { Rewrites(filtered: filtered) }
            // The colour is the whole of the difference, as everywhere else in this app: the words
            // alone in the state's own colour, never a label inside a capsule that reads as
            // something you press — and there is a real button an inch below this one.
            if let refusal = filtered?.refusal { aside(refusal, in: Palette.lcdRed) }
            if !snaps.isEmpty { pinned }
            if compact { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? Spacing.extraSmall : Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(accent.opacity(0.4), lineWidth: 1)
        )
    }

    /// A deck column stays at `Radius.medium`: 20pt corners on a 240pt tile eat the tile.
    private var corner: CGFloat { compact ? Radius.medium : Radius.extraLarge }

    /// A line under the words, quiet, and in a deck column too: there is no size of card on which
    /// it is acceptable to show somebody a word they did not say without saying so.
    private func aside(_ words: String, in colour: Color) -> some View {
        Text(words)
            .font(Typography.hint)
            .foregroundStyle(colour)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What can be put in front of the words, and what can be pinned to them, above the words
    /// themselves.
    ///
    /// Two controls, not three. Photos and Clipboard are one question — where is the picture —
    /// asked twice, and answering it took a third of the row to say so; they are one control
    /// now and the menu is where the two answers live.
    @ViewBuilder private var attachments: some View {
        if attach != nil || commands != nil {
            HStack(spacing: Spacing.small) {
                // First, because it goes at the front of the words: a command is the one part of
                // a prompt a phone cannot dictate — `/orchestrate-sessions` comes back as four
                // words and a guess — so it is picked from the Mac's own list and the rest is
                // still spoken. Deliberately not in the row at the foot: that row is what you do
                // with a finished prompt, and this is part of writing one.
                if commands != nil {
                    Button { choosing = true } label: {
                        Attach(word: "Command", symbol: "slash.circle", compact: compact)
                    }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("pick-command")
                }
                if attach != nil { pictures }
                Spacer(minLength: 0)
            }
            .font(Typography.hint)
            .foregroundStyle(accent)
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
    @ViewBuilder private var pictures: some View {
        if let attach {
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
