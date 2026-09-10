import DeckhandKit
import SwiftUI

/// A slip's questions as cards, each with the app's own talk mark on it.
///
/// This is the same slip as any other — same screen, same furniture, same receipt, same answer on
/// its way to the same file. What is different is that the questions were declared rather than
/// drawn (`Aloud`), so the app can put its own controls against them instead of handing the page a
/// web view and hoping it drew something a thumb can hit.
///
/// The mark is the mark. Not a picture of one, not an HTML button styled to look like one: the
/// same `TalkControl` and `TalkMark` the session page uses, so hold-versus-tap is the setting the
/// person already chose and the thing under their thumb behaves the way it does everywhere else.
///
/// One recorder for the whole screen, and `isMine` is what keeps ten marks from all lighting up at
/// once — the same arrangement the deck uses for its columns. A card is "mine" only while it is the
/// one being talked into, so every other mark stays at rest and stays teal.
///
/// Every card carries a field as well as a mark. Speaking is the point and typing is the fallback,
/// but the fallback has to exist: an answer with one wrong word in it should not need saying twice,
/// and the field is where the person fixes it. Words land *under* what is already there, never
/// over it — `Underneath.words`, the same rule as every other dictated field in this app.
struct AloudCards: View {
    let aloud: Aloud
    /// The listing's recorder, the gesture the person set, and the way a clip becomes words.
    /// Handed down rather than made here: a recorder rebuilt mid-clip is a clip on the floor.
    let say: Dictation
    /// What the person answered last time, per question. Read into the fields once, at build
    /// time, so an answered slip that is reopened is already holding its answers.
    let was: [String: String]
    /// The answer, as the JSON text of it. Awaited, and it says whether the answer actually went:
    /// a web page answers and then calls `deckhand.close()` itself, and a card stack has no page
    /// to do that for it. Without the receipt this button fired, delivered, and looked dead —
    /// which is a button somebody presses again, and again, each press a fresh answer.
    let respond: (String) async -> Bool

    @State private var said: [String: String]
    /// Which question the recorder is currently working for, or none. What makes one card's mark
    /// live while the other nine stay at rest.
    @State private var recording: String?
    /// The one question a clip came back empty for. Said on the card rather than in `model.status`,
    /// which is two screens behind this one.
    @State private var nothing: String?
    @FocusState private var editing: String?
    /// On the wire. The one thing that must be visible from the button itself: it is at the foot
    /// of a long scroll, and the receipt this screen already had is in the bar at the top of it.
    @State private var sending = false

    init(aloud: Aloud,
         say: Dictation,
         was: [String: String],
         respond: @escaping (String) async -> Bool) {
        self.aloud = aloud
        self.say = say
        self.was = was
        self.respond = respond
        _said = State(initialValue: was)
    }

    /// How many questions have something in them. What the send button counts, and it counts the
    /// same way `Aloud.value` does — blank is unanswered, here and on the wire.
    private var answered: Int {
        said.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.small) {
                ForEach(Array(aloud.questions.enumerated()), id: \.element.id) { index, question in
                    card(question, at: index)
                }
                foot
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.large)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func card(_ question: Aloud.Question, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            head(question, at: index)
            mark(question)
            field(question)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.surfacePrimary)
        )
        .accessibilityIdentifier("aloud-card")
    }

    private func head(_ question: Aloud.Question, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("\(index + 1) OF \(aloud.questions.count)")
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.textTertiary)
            Text(question.ask)
                .font(Typography.subtitle)
                .foregroundStyle(Palette.textPrimary)
            if !question.hint.isEmpty {
                Text(question.hint)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The mark, centred, with nothing beside it. The accent is this card's rather than the
    /// screen's: the one being talked into goes utt orange and the other nine stay teal, which is
    /// the only way ten of these on one screen say which one is listening.
    private func mark(_ question: Aloud.Question) -> some View {
        TalkControl(
            recorder: say.recorder,
            mode: say.mode,
            isMine: recording == question.id,
            onStart: {
                editing = nil
                nothing = nil
                recording = question.id
            },
            onClip: { await heard($0, for: question) },
            content: { TalkMark(state: $0, level: say.recorder.level) }
        )
        .accent(Palette.accent(recording: recording == question.id && say.recorder.isRecording))
        .frame(maxWidth: .infinity)
    }

    /// What was heard, and the way to fix a word of it. Always here, not only once something has
    /// been said: a question you would rather type than say is still a question to answer.
    private func field(_ question: Aloud.Question) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            TextField("Hold the mark and say it", text: binding(question), axis: .vertical)
                .font(Typography.primaryRow)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...8)
                .focused($editing, equals: question.id)
                .padding(Spacing.small)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(Palette.tileIdle)
                )
                .accessibilityIdentifier("aloud-answer")
            if nothing == question.id {
                Text("Nothing heard — say it again")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.lcdRed)
            }
        }
    }

    /// The way to send, at the end of the questions rather than on a bar over them. A band of
    /// furniture across the page to hold one button is the thing this app takes out of every
    /// screen it can, and the last card is where somebody who has answered them is already looking.
    private var foot: some View {
        VStack(spacing: Spacing.extraSmall) {
            Button { send() } label: {
                Text(word)
                    .font(Typography.primaryRow)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(idle ? Palette.textTertiary : Palette.tint))
            }
            .buttonStyle(.plain)
            // Both, and the second one matters: without it a tap while the first answer is still
            // on the wire sends a second one, and every send is a message into the session.
            .disabled(answered == 0 || sending)
            .accessibilityIdentifier("aloud-send")
            // Said plainly rather than left to be discovered: a slip can be answered more than
            // once, and half of these are worth sending before the other half are thought about.
            Text("You can send what you have and add the rest later")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.top, Spacing.small)
    }

    private func binding(_ question: Aloud.Question) -> Binding<String> {
        Binding(get: { said[question.id] ?? "" }, set: { said[question.id] = $0 })
    }

    private func heard(_ clip: URL, for question: Aloud.Question) async {
        recording = nil
        guard let words = await say.words(clip) else {
            nothing = question.id
            return
        }
        said[question.id] = Underneath.words(words, under: said[question.id] ?? "", gap: " ")
    }

    /// Grey while there is nothing to send and while one is going: a filled capsule that does
    /// nothing when pressed is the thing this whole fix is about.
    private var idle: Bool { answered == 0 || sending }

    private var word: String {
        if sending { return "Sending…" }
        return answered == aloud.questions.count
            ? "Send all \(answered)"
            : "Send \(answered) of \(aloud.questions.count)"
    }

    private func send() {
        editing = nil
        guard !sending, let json = Aloud.value(of: said) else { return }
        sending = true
        Task {
            _ = await respond(json)
            sending = false
        }
    }
}
