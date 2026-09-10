import DeckhandKit
import Foundation

/// What it takes for the review card to hear the rest of a thought: the page's own recorder, the
/// gesture the person set, and where the finished clip goes.
///
/// One value rather than three parameters, because the card can draw that button only if it has
/// all three and not one of them is any use on its own. The recorder has to be the page's: the
/// card is rebuilt the moment the words in it change, and a recorder rebuilt mid-clip is a clip
/// on the floor.
struct SayMore {
    let recorder: Recorder
    let mode: TalkMode
    /// The clip, and the words the card is holding as they stand on screen.
    let heard: (URL, String) async -> Void
}

/// How words get into the review card *underneath* the words already in it.
///
/// Two things put them there — a marked-up picture, from `Markups.swift`, and saying the rest of
/// a thought out loud — and both mean the same thing: what is in the card stays where it is and
/// the new words go below it. The path that *replaces* what is in the card is `hold`, in
/// `Filtering.swift`. Keeping the two apart in two files is what stops a second clip from
/// quietly eating the first.
@MainActor
extension AppModel {
    /// Beneath whatever is already in the card, never instead of it.
    ///
    /// You dictate first and add the rest second about as often as the other way round, and the
    /// one thing that must not happen is a sentence you spoke vanishing because you then said
    /// another. Underneath keeps the order you said things in, and the blank line makes the two
    /// read as two paragraphs rather than as one run-on.
    ///
    /// The joining itself is `Underneath.words`, over in DeckhandKit where `just test` can reach
    /// it: every field in this app that can be spoken into goes through the same three lines, and
    /// they are the three lines that lose somebody's work when they are wrong.
    func append(_ prose: String, to session: Session) {
        review[session.sessionId] = Underneath.words(prose,
                                                    under: review[session.sessionId] ?? "",
                                                    gap: "\n\n")
    }

    /// The words as they stand on screen, made the model's own before anything is laid under them.
    ///
    /// An edit made by hand lives in the card until Send — `review` still holds the transcript that
    /// was corrected, and the card shows its own copy. So anything that adds words from outside the
    /// card has to fold the correction in first, or the two diverge and the one that gets sent is
    /// the one without the addition in it. `append(clip:to:beneath:)` does this inline for a second
    /// clip; marking up a picture already pinned to the card needs it for the same reason, a moment
    /// earlier: at the tap, so that closing the sheet without marking anything still leaves the
    /// correction where it was.
    func settle(_ said: String, for session: Session) {
        review[session.sessionId] = said
    }

    /// Another clip, transcribed and laid under the words the card is already holding.
    ///
    /// `said` is those words as they stand on screen, which is not always what is in `review`: an
    /// edit made by hand lives in the card until Send. It is written back before anything else
    /// happens, so the new half lands under the *corrected* half rather than under the transcript
    /// that was corrected — and so all of it survives the card being rebuilt, which a rotation is.
    ///
    /// Nothing is delivered. `deliver: false` is the review card's own way through the Mac, the
    /// same one the first clip took, so there is no new endpoint behind this. The card stays up
    /// holding what it has for the whole of it, which means a clip that fails to record, to
    /// transcribe or to arrive costs nothing but the saying of it again.
    func append(clip: URL, to session: Session, beneath said: String) async {
        guard let client = settings.client(), let kept = keep(clip, for: session) else { return }
        review[session.sessionId] = said
        status = "Transcribing…"
        // The clip is on the wire: locking here suspends the app and loses it.
        Awake.hold()
        defer { Awake.release() }
        await run {
            let receipt = try await client.upload(clip: self.archive.url(of: kept),
                                                  to: session.sessionId,
                                                  route: self.preferences.route,
                                                  deliver: false)
            // The card now holds this clip's words too, so Send speaks for both of them. A throw
            // never reaches here and does not need to: the recording is already filed, and an
            // entry with no transcript on it is exactly what "never got past the Mac" looks like.
            self.heldClips[session.sessionId, default: []].append(kept.id)
            self.archive.finish(kept.id, transcript: receipt.words, delivered: false, failure: nil)
            if let words = receipt.words {
                self.append(words, to: session)
                self.reviewFiltered[session.sessionId] = self.standing(receipt, for: session)
                // And the cost goes, for the reason the note does: it is what one clip cost,
                // and the card now holds two. A total standing under words half of it never
                // measured is the same lie in numbers.
                self.reviewTiming[session.sessionId] = nil
            }
            self.status = self.outcome(of: receipt, to: session, held: true)
        }
    }

    /// What the chain's two lines still mean once a second clip has landed in the card.
    ///
    /// The note does not survive. It says what the chain changed in one pass over one clip, and a
    /// sentence about half the words in the card, sitting underneath all of them, is the exact lie
    /// the card exists to prevent. What the chain made of this clip alone goes to the status line
    /// instead, where every other per-clip outcome in this app already goes.
    ///
    /// A refusal does survive, either way round: it says something in there will not pass, and
    /// adding words to it cannot make that untrue. So the one already on screen stands, and a
    /// fresh one takes its place only when there was none.
    private func standing(_ receipt: UploadReceipt, for session: Session) -> Filtered {
        let stands = reviewFiltered[session.sessionId]?.refusal
        let fresh = receipt.stoppedBy.map { refusal(by: $0, because: receipt.deliveryError) }
        return Filtered(note: nil, refusal: stands ?? fresh)
    }
}
