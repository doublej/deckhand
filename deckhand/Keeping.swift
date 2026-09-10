import DeckhandKit
import Foundation

/// A clip's whole journey, from the moment it stops recording.
///
/// It used to begin in the temporary directory and stay there until an upload succeeded, and the
/// upload ran inside `run`, which swallows a throw — so a sleeping Mac, a rejected token or a
/// timeout left the file in `tmp` with nothing referencing it, and the words nowhere at all. Every
/// clip is therefore filed in the archive *before* it goes on the wire, and every outcome the Mac
/// can give is written back onto its entry. Nothing here deletes a clip; only the sweep and
/// the person do that. `ClipArchive` is the filing itself, over in DeckhandKit where `just test`
/// can reach it.
@MainActor
extension AppModel {
    /// The clip, filed, with what happened to it laid on afterwards.
    ///
    /// A clip that cannot even be moved into the archive is the one case worth stopping for: the
    /// alternative is uploading from a place nothing is keeping, which is the bug this replaces.
    ///
    /// `spans` is what the recorder already measured of this clip — the microphone opening, the
    /// clip's own length, closing the file. Handed in rather than fetched because the recorder
    /// belongs to the screen the mark is on, and the model has never held one.
    func upload(clip: URL, to session: Session, spans: PhoneSpans = PhoneSpans()) async {
        guard let client = settings.client() else { return }
        var spans = spans
        let filing = Date.now
        guard let kept = keep(clip, for: session) else { return }
        spans.keeping = PhoneSpans.since(filing)
        let confirms = preferences.confirms
        status = confirms ? "Transcribing…" : "Sending to \(session.name)…"
        logger.info("uploading clip for \(session.name, privacy: .public)")
        // The clip is on the wire: locking here suspends the app and loses it.
        Awake.hold()
        defer { Awake.release() }
        await deliver(kept, to: session, with: client, confirms: confirms, spans: spans)
    }

    /// Its own step because `run` is not enough here. That helper reports a throw and lets it go,
    /// which is precisely how the old clip went missing: the failure has to reach the entry, or a
    /// clip sits in the list saying nothing about why it never arrived.
    private func deliver(_ kept: KeptClip,
                         to session: Session,
                         with client: DeckhandClient,
                         confirms: Bool,
                         spans: PhoneSpans) async {
        var spans = spans
        do {
            let sent = Date.now
            let receipt = try await client.upload(clip: archive.url(of: kept),
                                                  to: session.sessionId,
                                                  route: preferences.route,
                                                  deliver: !confirms,
                                                  seconds: spans.spoken / 1000)
            spans.upload = PhoneSpans.since(sent)
            logger.info("transcript: \(receipt.transcript ?? "none", privacy: .public)")
            note(receipt, cost: spans, on: kept.id, for: session)
            file(receipt, onto: kept, for: session, confirms: confirms)
            received(receipt, for: session, confirms: confirms)
        } catch {
            archive.finish(kept.id, transcript: nil, delivered: false, failure: reason(error))
            status = reason(error)
            logger.error("clip kept, upload failed: \(String(describing: error))")
        }
    }

    /// What the whole journey cost, onto the clip and onto the card.
    ///
    /// Both, because they are read in two places and neither can reach the other: the archive
    /// is a file and the card is redrawn on every keystroke of an edit.
    private func note(_ receipt: UploadReceipt,
                      cost spans: PhoneSpans,
                      on clip: String,
                      for session: Session) {
        let timing = ClipTiming.merged(phone: spans,
                                       mac: receipt.timings,
                                       macTotal: receipt.macTotal)
        archive.record(timing, on: clip)
        reviewTiming[session.sessionId] = timing
    }

    /// What the Mac made of the clip, onto the clip.
    ///
    /// Words held for reading are filed as not yet delivered rather than as a failure: nothing has
    /// gone wrong, the person simply has not pressed Send. The entry is remembered against the
    /// session so that pressing it can come back and say so — see `markSent(for:)`.
    private func file(_ receipt: UploadReceipt,
                      onto kept: KeptClip,
                      for session: Session,
                      confirms: Bool) {
        let held = receipt.words != nil && (confirms || receipt.stoppedBy != nil)
        // Replaced, never appended: `hold` puts these words *instead of* whatever the card was
        // holding, so anything it was standing for is not what Send is about to say. Appending
        // here would mark a clip whose words were thrown away as having reached its session, and
        // the sweep would then drop the clip a week later — the one outcome to avoid.
        if held { heldClips[session.sessionId] = [kept.id] }
        // The last span of the whole path ends in a view appearing, so it is started here and
        // closed by the card itself. Only where a card is coming: a clip sent outright has none.
        answeredAt[session.sessionId] = held ? .now : nil
        archive.finish(kept.id,
                       transcript: receipt.words,
                       delivered: receipt.went,
                       failure: receipt.went || held ? nil : outcome(of: receipt, to: session))
    }

    /// Either it is already on its way, or it is waiting to be read first.
    ///
    /// Words are held for two reasons and they meet here: because reading first is the setting,
    /// and because a filter refused them — a refusal on the way out is still words that exist and
    /// were said to nobody, and the card is the one place in this app that can hold those.
    private func received(_ receipt: UploadReceipt, for session: Session, confirms: Bool) {
        guard let text = receipt.words, confirms || receipt.stoppedBy != nil else {
            status = outcome(of: receipt, to: session)
            // Fetch rather than fake it: the words are in the session's own transcript within
            // a moment, and showing them from there means they are shown once, in order, and
            // looking like every other thing said in this conversation.
            if receipt.went { Task { await self.loadTurns(for: session) } }
            return
        }
        // What the chain made of them, not what utt heard, and what the chain said about them
        // alongside: a word the card shows differing silently from the word that was spoken is
        // the lie this card exists to prevent.
        // `heard` is what utt gave before this Mac's chain swapped anything, and `raw` what the
        // recogniser gave before utt's own pipeline did — the second is nil on every Mac today.
        // `uttRewrote` asks utt's `stages`, not `raw != text`: the pipeline trims, and trimming
        // is not something to show a person a before-and-after of.
        hold(text,
             for: session,
             notes: receipt.notes,
             stoppedBy: receipt.stoppedBy,
             because: receipt.deliveryError,
             heard: receipt.transcript,
             raw: receipt.uttRewrote ? receipt.raw : nil,
             uttStages: receipt.uttStages)
        status = outcome(of: receipt, to: session, held: confirms)
    }

    // MARK: - the archive, from the rest of the app

    /// Files a clip and says so when it could not, rather than throwing into a caller that has
    /// nowhere useful to put it. Nil is the one case where there is no clip to lose.
    func keep(_ clip: URL, for session: Session) -> KeptClip? {
        do {
            return try archive.keep(clip, for: session.sessionId, named: session.name)
        } catch {
            status = "Could not keep that clip: \(error.localizedDescription)"
            logger.error("archiving failed: \(String(describing: error))")
            return nil
        }
    }

    /// The card holding this clip's words is on screen. The one span nothing else here can
    /// measure, because it ends in SwiftUI drawing something.
    ///
    /// Answered once per clip: the card comes back on screen every time somebody swipes between
    /// panes, and only the first of those is the one the person waited for.
    func cardAppeared(for session: Session) {
        guard let answered = answeredAt.removeValue(forKey: session.sessionId),
              let clip = heldClips[session.sessionId]?.last else { return }
        archive.showed(clip, took: PhoneSpans.since(answered))
    }

    /// The words in a session's card have gone. The clips they came from can stop saying
    /// they never arrived, and the week the sweep counts starts for them here.
    func markSent(for session: Session) {
        archive.markSent(heldClips.removeValue(forKey: session.sessionId) ?? [])
    }

    /// The card was answered without sending. The clips stay exactly as they are — a clip
    /// nobody said is the clip this archive is most for — they simply stop belonging to a card.
    func unheld(for session: Session) {
        heldClips[session.sessionId] = nil
    }

    /// A transcript out of the archive, handed to a session by hand. A second chance at a prompt
    /// that never arrived, which is the whole reason the words were kept beside the audio.
    ///
    /// Prepared, because these words have been through the chain once already and have been on a
    /// screen since: a second pass would rewrite a prompt the person has read.
    func resend(_ kept: KeptClip, to session: Session) async {
        guard let client = settings.client(), let text = kept.transcript else { return }
        status = "Sending to \(session.name)…"
        await run {
            let sent = try await client.say(text,
                                            to: session.sessionId,
                                            route: self.preferences.route,
                                            prepared: true)
            guard sent.went else {
                self.status = sent.deliveryError ?? "\(session.name) did not take it"
                return
            }
            self.archive.markSent([kept.id])
            self.status = self.said("Sent to \(session.name)", notes: sent.notes)
        }
    }

    /// The clip itself, up to the Mac again, on whichever session is running now.
    ///
    /// `resend` is the sibling for a clip that already has words; this is for the one whose
    /// transcription failed, which has none to send and is the clip somebody most wants another
    /// go at. The audio is still here — every clip is filed before it goes on the wire and only
    /// what actually reached a session is ever swept — so this is the first attempt's own call
    /// against the same file, and the whole of the bookkeeping runs again with it.
    ///
    /// The entry is retargeted before the attempt, not after: the person has aimed the clip at
    /// this session, so the row names it whether or not it lands, and a second failure is written
    /// onto the row by `deliver` exactly as the first one was.
    func tryAgain(_ kept: KeptClip, on session: Session) async {
        guard let client = settings.client() else { return }
        archive.retarget(kept.id, to: session.sessionId, named: session.name)
        // Nothing was armed, recorded or filed this time round, so those spans are honestly zero.
        // The clip's own length is the one the Mac still needs: without it a line in
        // `timings.jsonl` cannot say what a millisecond bought.
        var spans = PhoneSpans()
        spans.spoken = kept.timings?.spoken ?? 0
        let confirms = preferences.confirms
        status = confirms ? "Transcribing…" : "Sending to \(session.name)…"
        logger.info("trying clip again on \(session.name, privacy: .public)")
        Awake.hold()
        defer { Awake.release() }
        await deliver(kept, to: session, with: client, confirms: confirms, spans: spans)
    }
}
