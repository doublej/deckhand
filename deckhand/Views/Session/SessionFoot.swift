import DeckhandKit
import SwiftUI

/// One slot at the foot of a session's page, and two things that can be in it: the mark you hold
/// to talk, or what it heard waiting to be read. Never both — while there is something to answer,
/// that is all this slot is for.
///
/// Its own file because `SessionView.swift` sat on the 300-line gate, and this is where the seam
/// is: everything above is what the session *is*, and this is the one thing you do to it.
struct SessionFoot: View {
    @Bindable var model: AppModel
    let session: Session
    /// The page's own recorder, not one of this view's: the slot is rebuilt the moment something
    /// is held for reading, and a recorder rebuilt mid-clip is a clip on the floor.
    @Bindable var recorder: Recorder

    var body: some View {
        Group {
            if model.review[session.sessionId] != nil { review } else { talk }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.bottom, Spacing.extraSmall)
    }

    /// The mark is the button. utt's mark, because recording is utt's job — it takes the
    /// recording tint and speeds up with the meter, exactly as it does in utt's own rail.
    private var talk: some View {
        TalkControl(
            recorder: recorder,
            mode: model.preferences.talkMode,
            isMine: true,
            onStart: { model.status = "Recording for \(session.name)" },
            onClip: { await model.upload(clip: $0, to: session) },
            content: {
                TalkMark(state: $0,
                         level: recorder.level,
                         confirms: model.preferences.confirms)
            }
        )
    }

    /// Held for reading, over the top of whichever tab you were on — including the button you
    /// were holding to record. Nothing else on the page can be acted on until this is answered,
    /// so covering it is honest rather than rude: it was the foot of the transcript before,
    /// which meant scrolling to reach the thing the app was waiting on.
    @ViewBuilder private var review: some View {
        if let text = model.review[session.sessionId] {
            ReviewCard(
                text: text,
                target: session.name,
                send: { edited in Task { await model.send(edited, to: session) } },
                discard: { model.discard(for: session) },
                filtered: model.reviewFiltered[session.sessionId],
                snaps: model.snaps(for: session),
                attach: { model.attach($0, to: session) },
                paste: { model.attachFromClipboard(to: session) },
                unattach: { model.unattach($0, from: session) }
            )
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
