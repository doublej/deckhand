import DeckhandKit
import Foundation

/// What it takes to say words into a field rather than into a session: the page's own recorder,
/// the gesture the person set, and the one way a clip becomes words on this Mac.
///
/// One value rather than three parameters, for the reason `SayMore` is one: a field can offer to be
/// spoken into only if it has all three and not one of them is any use on its own. Optional at
/// every call site, because a surface with no session behind it — the pairing page — has nowhere
/// to send a clip and says so by offering nothing.
///
/// The recorder is always the page's, handed down into whatever sheet the field is on. Never one
/// the control makes for itself: a recorder rebuilt mid-clip is a clip on the floor, and a page
/// whose accent is derived from a recorder it is not holding stays teal while somebody talks.
struct Dictation {
    let recorder: Recorder
    let mode: TalkMode
    /// One clip to words, or nil where nothing came back.
    let words: (URL) async -> String?
}

@MainActor
extension AppModel {
    /// A clip transcribed on the Mac and handed straight back, delivered nowhere.
    ///
    /// `deliver: false` is the review card's own way through the Mac and this takes the same one,
    /// so there is no new endpoint behind dictating into a field — and no session's inbox is
    /// touched by renaming it or by typing a word into a filter.
    ///
    /// It is `words` rather than `transcript`, so the chain's own corrections come with it: the
    /// filter that swaps the words dictation keeps getting wrong is the cheapest accuracy in this
    /// system and a field wants it as much as a prompt does. `stoppedBy` is not consulted — a
    /// refusal is about delivery, and this delivers nothing.
    func dictated(_ clip: URL, for session: Session) async -> String? {
        guard let client = settings.client() else { return nil }
        status = "Transcribing…"
        // The clip is on the wire: locking here suspends the app and loses it.
        Awake.hold()
        defer { Awake.release() }
        // Out here rather than after the upload, because `run` swallows a throw and the removal
        // would then never happen — the clip would sit in `tmp` with nothing referencing it. This
        // one is not archived: a dictated clip is spoken into a field the person is looking at, so
        // nothing came back is a visibly empty field and not work quietly lost.
        defer { try? FileManager.default.removeItem(at: clip) }
        var heard: String?
        await run {
            let receipt = try await client.upload(
                clip: clip, to: session.sessionId, route: self.preferences.route, deliver: false
            )
            heard = receipt.words
            // The one place this can be read is the rail, behind whatever sheet the field is on.
            // The control itself says it is listening and says it is waiting; what it cannot say
            // is why nothing came back, and that sentence belongs where every other one goes.
            self.status = heard.map { _ in self.said("Heard it", notes: receipt.notes) }
                ?? (receipt.transcriptError ?? "Nothing heard")
        }
        return heard
    }
}
