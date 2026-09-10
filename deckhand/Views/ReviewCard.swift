import DeckhandKit
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
    @State private var editing = false
    @State private var choosing = false
    /// Set by `SayRest` while a clip it took is with the Mac. See `waiting`.
    @State private var adding = false
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
                // Twice the stack's own spacing under it. This line belongs to the box above
                // — two more ways of filling it — and at eight points on both sides it read as
                // the top of the button row instead, which is the one group it is not part of.
                attachments
                    .padding(.horizontal, Self.gutter)
                    .padding(.bottom, Spacing.extraSmall)
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

    /// Edit, at the foot of the box on the right, drawn the way `SayRest` is drawn.
    ///
    /// A glyph and a word with nothing behind them: this is the quietest of the three things you
    /// can do — it neither sends nor throws away, it just opens the words. 44pt of finger under
    /// 11pt of ink, the trade `SayRest` makes. No trailing padding, so it ends on the column the
    /// words above it end on.
    private var openWords: some View {
        Button { editing = true } label: {
            Label("Edit", systemImage: "square.and.pencil")
                .font(Typography.hint)
                .foregroundStyle(accent)
                .lineLimit(1)
                .chip(.clear)
                // Pulled back by its own trailing inset, the mirror of what `SayRest` does on
                // the leading side: the chip is what makes the two boxes match, and neither may
                // pay for it by moving off the column it sits on.
                .padding(.trailing, -Chip.insets.trailing)
                // Bottom of the box, for the reason `SayRest.face` gives: these two sit on the
                // card's foot row and centred ink floats above the edge it belongs on.
                .frame(minHeight: Self.touch, alignment: .bottomTrailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit-prompt")
    }

    /// The minimum a finger can be asked to hit. The same raw number `ReviewActions`, `SayRest`
    /// and `FilesView` write, and for the same reason: no spacing token means "a finger".
    private static let touch: CGFloat = 44

    /// The one left edge everything on this card is set against.
    ///
    /// It is the box's own padding, so the prompt starts here — and anything that does not is a
    /// second column. There were three: the words at 16, Discard at 8, and the two attach
    /// controls flush against the box's outer edge, reading as three unrelated groups rather
    /// than one card. Filled shapes are the exception and align by their own edge, which is
    /// where Send's trailing edge comes from: ink lines up with text, a capsule with the box.
    private static let gutter = Spacing.medium

    private var actions: some View {
        ReviewActions(route: target,
                      words: words,
                      discard: discard,
                      edit: { editing = true },
                      send: send,
                      compact: compact,
                      waiting: waiting)
    }

    /// Whether another sentence is still on its way into these words: the microphone is open, or
    /// the clip is with the Mac and its words are not back. Sending in either state posts the
    /// prompt without the part being added to it, and the missing sentence then arrives in the
    /// session on its own a moment later. Recording is read straight off the recorder because the
    /// slot holds the mark or this card and never both, so nothing else can be listening.
    private var waiting: Bool {
        guard let more else { return false }
        return more.recorder.isRecording || adding
    }

    /// The prompt itself, in the box, and the one control that changes it in the corner.
    ///
    /// Command and Add-attachments used to head this stack and are under the box now. They are
    /// not the prompt — they are two ways of putting something into it — and heading the card
    /// with them meant the first thing read inside the box was not what was said. Under it they
    /// sit with the other things you do to a held prompt, and the box holds only the prompt.
    ///
    /// Edit came the other way, out of the row of buttons and into the corner. It was a filled
    /// half-width pill beside Send, which made it look like a decision of the same weight; it is
    /// not, it is a way into the words themselves. In the corner of the box holding those words
    /// it is where the thing it changes is, and it is drawn like `SayRest` — glyph, word, no
    /// fill — because the two are the same kind of thing: they alter the prompt rather than
    /// dispose of it.
    private var staging: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
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
                // The box's own foot: add to the words on the left, open them on the right.
                //
                // Edit was a row of its own above the words, which put it in a 44pt band of
                // nothing with the prompt pushed down under it. Down here it is on the line the
                // words end on, opposite the control that continues them — the two read as the
                // pair they are: the only things here that change the prompt rather than
                // dispose of it.
                HStack(spacing: 0) {
                    if let more { SayRest(more: more, words: words, adding: $adding) { draft = nil } }
                    Spacer(minLength: Spacing.small)
                    if !compact { openWords }
                }
                // Down into the box's own bottom padding. Bottom-aligned in a 44pt frame the
                // ink still stood 20 points off the edge — the padding is the card's and the
                // controls were sitting on top of it rather than into it. The touch boxes move
                // with them and stay inside the card.
                .padding(.bottom, -Spacing.extraSmall)
            }
            // Under the words, quiet, and in a deck column too: there is no size of card on which
            // it is acceptable to show somebody a word they did not say without saying so.
            if let note = filtered?.note { aside(note, in: Palette.textTertiary) }
            // What the note cannot say: the sentence those words replaced. Without it a swap
            // that was wrong reads as a mishearing, and a mishearing as a swap.
            if let filtered, !compact { Rewrites(filtered: filtered, prepared: text) }
            // The colour is the whole of the difference, as everywhere else in this app: the words
            // alone in the state's own colour, never a label inside a capsule that reads as
            // something you press — and there is a real button an inch below this one.
            if let refusal = filtered?.refusal { aside(refusal, in: Palette.lcdRed) }
            if !snaps.isEmpty {
                PinnedStrip(snaps: snaps, compact: compact) { snap in
                    mark?(snap, words)
                    // Handed over, so the card reads them out of the model from here
                    // on — which is where the remarks about it are about to land.
                    draft = nil
                }
            }
            if compact { actions }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? Spacing.extraSmall : Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
    }

    /// A deck column stays at `Radius.medium`: 20pt corners on a 240pt tile eat the tile.
    private var corner: CGFloat { compact ? Radius.medium : Radius.extraLarge }

    // The teal border that used to ring this is gone: `SessionFoot` lays a blurred ground under
    // the whole slot now, so the ring had become a second edge saying what the ground says.

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
                if let attach { PictureMenu(attach: attach, paste: paste, compact: compact) }
                Spacer(minLength: 0)
            }
            .font(Typography.hint)
            .foregroundStyle(accent)
        }
    }

}
