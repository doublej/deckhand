import DeckhandKit
import PhotosUI
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
    /// Which pinned picture is being marked up, if any. Here rather than in the card because the
    /// card holds no model and no session, and the marking sheet needs both.
    @State private var marking: Pinned?
    /// Whether the archive is open. Presented from this slot because this slot holds the mark the
    /// gesture is on, and the archive is about every clip rather than about this session.
    @State private var browsing = false
    /// Whether the press that is not talking has been made. It went straight to the archive; there
    /// are three things behind it now, so what it opens is the list of them.
    @State private var reaching = false
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []

    var body: some View {
        Group {
            if model.review[session.sessionId] != nil { review } else { talk }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.bottom, Spacing.extraSmall)
        .background(backdrop)
        .sheet(item: $marking) { SnapView(model: model, session: $0.session, snap: $0.snap) }
        .sheet(isPresented: $browsing) { ArchiveSheet(model: model) }
        .confirmationDialog("", isPresented: $reaching, titleVisibility: .hidden) { reach }
        .photosPicker(isPresented: $picking,
                      selection: $picked,
                      maxSelectionCount: nil,
                      selectionBehavior: .ordered,
                      matching: .images,
                      photoLibrary: .shared())
        .onChange(of: picked) { _, items in pin(items) }
    }

    /// The three things the press that is not talking can do, the nearest thumb last.
    ///
    /// A `.confirmationDialog` and deliberately **not** a `.contextMenu`: a context menu installs
    /// a long press of its own, and a long press applied over this control takes the touch from
    /// the tap under it — which is exactly how tap-to-talk broke once already. The press stays
    /// the one `TalkGesture` already owns, and all that changed is what it opens.
    ///
    /// Clips is last because a dialog stacks upwards from the bottom of the screen, so the last
    /// entry is the one a thumb coming off the mark meets first — and it is the one that was here
    /// before, which should not cost a reach as well as a press. The two picture words are the
    /// review card's own, so the two ways to the same two verbs are recognisably the same thing.
    ///
    /// Nothing says any of this at rest. The mark says nothing at rest, and this is discovered by
    /// holding it exactly as the archive already was.
    @ViewBuilder private var reach: some View {
        Button("Photos") { picking = true }
        Button("Clipboard") { model.attachFromClipboard(to: session) }
        Button("Clips") { browsing = true }
    }

    /// The picker hands back items, not bytes, and the bytes come over a moment later. One at a
    /// time and in the order they were chosen, so the card opens on the first picture rather than
    /// after the slowest one — and `attach` is what opens it, since from here there is no card.
    private func pin(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                if let bytes = try? await item.loadTransferable(type: Data.self),
                   let snap = Snap(picked: bytes) {
                    model.attach(snap, to: session)
                }
            }
            picked = []
        }
    }

    /// The mark is the button. utt's mark, because recording is utt's job — it takes the
    /// recording tint and speeds up with the meter, exactly as it does in utt's own rail.
    ///
    /// Nudged down into the safe area, and only the row the mark is in: it sat a whole home
    /// indicator's height clear of the bottom, which on a screen whose content now runs all the
    /// way down read as floating in the middle of nothing. The review card does not move — it is
    /// tall, and pushing its foot under the indicator would put Send where the system's own
    /// gesture lives.
    ///
    /// The arithmetic, because the floor here is an interaction boundary and not taste. The stack
    /// this slot is an overlay on ends at the safe area, 34pt above the glass on this phone; the
    /// slot's own `Spacing.extraSmall` puts the row's bottom edge 8pt above that. So the offset
    /// is measured down from 42pt, the system's swipe-up zone is the bottom 20pt, and **22 is the
    /// ceiling**. `Spacing.medium` leaves 26pt of glass under the row — 6pt of margin over that
    /// zone — where `Spacing.large` would put the row inside it.
    ///
    /// The one surface that also carries the press talking does not use: it is the only place a
    /// mark has no other job for it. A row in the sessions list spends its tap on opening the
    /// session and a deck column spends its own, so neither is handed one.
    private var talk: some View {
        TalkControl(
            recorder: recorder,
            mode: model.preferences.talkMode,
            isMine: true,
            onReach: { reaching = true },
            onStart: { model.report("Recording for \(session.name)", to: session) },
            onClip: { await model.upload(clip: $0, to: session, spans: recorder.spans) },
            content: {
                TalkMark(state: $0,
                         level: recorder.level,
                         confirms: model.preferences.confirms)
            }
        )
        .offset(y: Spacing.medium)
    }

    /// The ground the held card stands on, and nothing at all the rest of the time.
    ///
    /// The card's own pieces do not all have a fill: Discard has none by design, and the
    /// round-trip line is a line. Standing them over a live transcript put words on words —
    /// "Discard" over "RUNNING" — which is the one thing a control that throws work away must
    /// never be. Giving each piece its own tile would be four tiles and four edges; one ground
    /// under the whole slot is the same fix once.
    ///
    /// Material rather than a colour, because this covers a transcript that is still moving
    /// underneath: a flat fill would read as a panel that appeared, and blurred glass reads as
    /// the page still being there and out of reach — which is exactly what is true while a card
    /// is waiting to be answered. It runs the full width and down through the safe area, past
    /// the slot's own padding, so no strip of transcript shows around the edges.
    ///
    /// The top edge is faded rather than cut. A hard horizontal line across the middle of a
    /// transcript reads as a rendering fault; a long gradient reads as depth.
    ///
    /// **The ramp is eased, not just long.** A two-stop `clear → black` gradient changes alpha at
    /// a constant rate, so however far you stretch it there is still a line at the top where the
    /// dimming visibly starts — which is the edge this exists to remove. The stops below are
    /// roughly quadratic: almost nothing for the first quarter, then gathering. That is what makes
    /// it read as tapering rather than as a band, and it is why lengthening `Spacing.large` alone
    /// did not fix it.
    @ViewBuilder private var backdrop: some View {
        if model.review[session.sessionId] != nil {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        LinearGradient(stops: Self.taper, startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.fade)
                        Rectangle()
                    }
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// How far the backdrop takes to arrive. Three times what it was: at 24 points the transition
    /// happened inside one line of transcript, which is a band across a word rather than a fade.
    private static let fade: CGFloat = 72

    /// Quadratic-ish, so the first points are nearly clear and the last are nearly solid.
    private static let taper: [Gradient.Stop] = [
        .init(color: .clear, location: 0),
        .init(color: .black.opacity(0.06), location: 0.25),
        .init(color: .black.opacity(0.25), location: 0.5),
        .init(color: .black.opacity(0.56), location: 0.75),
        .init(color: .black, location: 1)
    ]

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
                cost: model.reviewTiming[session.sessionId],
                snaps: model.snaps(for: session),
                attach: { model.attach($0, to: session) },
                paste: { model.attachFromClipboard(to: session) },
                mark: { snap, said in
                    model.settle(said, for: session)
                    marking = Pinned(snap: snap, session: session)
                },
                // The page's recorder again, and on purpose: the card is not allowed to make one
                // of its own for the same reason this view is not. Half a thought is a common way
                // to finish talking, and the whole point of the card is that the first half is
                // still here while the second is being said.
                more: SayMore(recorder: recorder,
                              mode: model.preferences.talkMode,
                              heard: { clip, said in
                                  await model.append(clip: clip, to: session, beneath: said)
                              }),
                // And again for the editor behind Edit, which is a field rather than the card:
                // the same recorder, a clip that is only ever turned into words.
                say: Dictation(recorder: recorder,
                               mode: model.preferences.talkMode,
                               words: { await model.dictated($0, for: session) }),
                // The names this session answers to, for the front of the words. Fetched when
                // the picker opens rather than held here: two hundred of them, and most cards
                // never ask.
                commands: { await model.commands(for: session) },
                // The Mac's word list, so the sheet can say what is already on it and correct a
                // row rather than doubling it.
                aliases: model.wants.aliases,
                alias: { model.storeAliases($0) }
            )
            .frame(maxWidth: .infinity)
            // Read when a card appears rather than polled: nothing but this phone changes it,
            // and a sheet offering to alias a word it has already been told about is the one
            // thing this list gets wrong.
            .task { await model.loadAliases() }
            // Down into the safe area, the same move the mark makes and inside the same ceiling.
            //
            // The arithmetic is `talk`'s, because the geometry is: the stack this slot overlays
            // ends 34pt above the glass, the slot's own `Spacing.extraSmall` puts its bottom edge
            // 8pt above that, so there are 42 points under it and the system's swipe-up zone is
            // the last 20 — **22 is the ceiling**. 16 takes most of what is going and leaves the
            // zone alone.
            //
            // It was ruled out once, on the grounds that the card is tall and this would put Send
            // where the system's own gesture lives. That was true when Send was the last thing
            // here. It is not: the round-trip line sits under it now, so what reaches down into
            // the margin is a receipt — and the one control on this card that costs nothing to
            // press by accident is the right one to have nearest the edge.
            .offset(y: Spacing.medium)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            // The last span of the whole path: the Mac has answered, and here is the card.
            // It can only be closed from inside a view, which is the reason it is closed here.
            .onAppear { model.cardAppeared(for: session) }
        }
    }
}
