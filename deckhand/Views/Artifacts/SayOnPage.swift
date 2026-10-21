import DeckhandKit
import SwiftUI

/// One slot under a slip, and three things that can be in it: say something about the passage you
/// picked out, say what goes in the field you are standing in, or — the rest of the time — ask the
/// agent about the slip as a whole. Never two at once — a selection inside a field is the field's,
/// and WebKit reports no document selection for one, so the page can only ever be holding one.
///
/// Asking is always there because a slip's answers are absolute: two buttons, and nothing for
/// "neither, because I don't follow". Without it the person goes back to the session, names the
/// slip they were just looking at, and asks there. It is not an answer — a decision stays open.
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
            case .quote: talking("Comment on what you selected", quoting: true)
            case .field: filling
            case .none: talking("Unclear? Hold and ask about this slip", quoting: false)
            }
        }
        .animation(Motion.arriving, value: talk.holds)
        .onChange(of: talk.holds) { nothing = nil }
    }

    /// The mark, because this is the same gesture as talking to the session — hold it, say the
    /// remark, let go. The words do not go to the session though: they go on the review card with
    /// the passage quoted above them, or with only the slip named when asking about all of it,
    /// which is what `PREVIEW` on its wing honestly says whatever the person's send-straight-away
    /// setting is. A remark about a slip nobody has read back is not a thing to fire off.
    private func talking(_ words: String, quoting: Bool) -> some View {
        VStack(spacing: Spacing.xxs) {
            caption(words)
            TalkControl(
                recorder: say.recorder,
                mode: say.mode,
                isMine: true,
                onStart: { Task { passage = quoting ? await talk.passage() : "" } },
                onClip: { await comment(on: $0) },
                content: {
                    TalkMark(state: $0, level: say.recorder.level,
                             saying: quoting ? "Comment on the selection" : "Ask about this slip")
                }
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
