import DeckhandKit
import SwiftUI

/// One slot under a slip, and two things that can be in it: say something about the passage you
/// picked out, or say what goes in the field you are standing in. Never both — a selection inside a
/// field is the field's, and WebKit reports no document selection for one, so the page can only ever
/// be holding one of the two.
///
/// Empty the rest of the time, and that is the point. The viewer has no browser chrome and is not
/// getting any: this appears because the page is holding something, and goes when it is not.
///
/// Its own file rather than a third job for `ArtifactView`, which is about the page arriving and what
/// became of an answer. This is about talking at one.
struct SayOnPage: View {
    @Bindable var model: AppModel
    let session: Session
    let artifact: Artifact
    /// The *listing's* recorder, handed down. Never one of this view's: this slot is rebuilt every
    /// time the page reports something different, and a recorder rebuilt mid-clip is a clip on the
    /// floor.
    let say: Dictation
    let talk: PageTalk
    /// What happens once a comment is on the card. The card is at the foot of the session's page,
    /// behind this screen, so there is nothing to see from here.
    let commented: () -> Void

    /// The passage, read out of the page the moment the person starts talking about it rather than
    /// when they stop. A tap anywhere in the page clears a selection, and the quote has to survive
    /// somebody steadying their thumb.
    @State private var passage = ""
    /// Why nothing landed, where nothing landed. `model.status` is the usual home for this and it is
    /// drawn on the rail, which is two screens behind this one — so from in here a clip that came
    /// back empty would look like a control that does nothing.
    @State private var nothing: String?

    var body: some View {
        Group {
            switch talk.holds {
            case .quote: quoting
            case .field: filling
            case .none: EmptyView()
            }
        }
        // Nothing, not an empty row: the padding and the width belong to the two things that can be
        // in the slot, or a page holding neither would still lose a strip off its bottom edge to an
        // inset with nothing in it.
        .animation(Motion.arriving, value: talk.holds)
        .onChange(of: talk.holds) { nothing = nil }
    }

    /// The mark, because this is the same gesture as talking to the session — hold it, say the
    /// remark, let go. The words do not go to the session though: they go on the review card with
    /// the passage quoted above them, which is what `PREVIEW` on its wing honestly says whatever the
    /// person's send-straight-away setting is. A quote nobody has read is not a thing to fire off.
    private var quoting: some View {
        VStack(spacing: Spacing.xxs) {
            caption("Comment on what you selected")
            TalkControl(
                recorder: say.recorder,
                mode: say.mode,
                isMine: true,
                onStart: { Task { passage = await talk.passage() } },
                onClip: { await comment(on: $0) },
                content: { TalkMark(state: $0, level: say.recorder.level) }
            )
            // The mark goes utt orange while it listens and the screen behind it stays teal, which
            // is what `SayInto` does on every sheet in this app: a cover keeps the tint, and the
            // control is the thing that changes.
            .accent(Palette.accent(recording: say.recorder.isRecording))
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.extraSmall)
    }

    /// The capsule, because a field wants filling in and not talking to. Straight into whichever
    /// field the page has focused, under whatever is already in it.
    private var filling: some View {
        VStack(spacing: Spacing.xxs) {
            caption("Say it instead of typing it")
            SayInto(say: say, heard: { await talk.say($0) })
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Spacing.extraSmall)
    }

    private func caption(_ words: String) -> some View {
        Text(nothing ?? words)
            .font(Typography.hint)
            .foregroundStyle(nothing == nil ? Palette.textTertiary : Palette.lcdRed)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.medium)
    }

    /// The remark, laid under whatever the card already held with the passage quoted above it.
    ///
    /// Words or nothing: a quote on its own is not a comment, so a clip that came back with nothing
    /// leaves the card exactly as it was and says so here. And `Quote.prose` is handed the passage
    /// as it stands — empty if the selection went — so what lands is true either way rather than a
    /// quote of something nobody can see.
    private func comment(on clip: URL) async {
        guard let words = await say.words(clip) else {
            nothing = "Nothing heard — say it again"
            return
        }
        model.append(Quote.prose(words, about: passage, from: artifact.title, id: artifact.id),
                     to: session)
        commented()
    }
}
