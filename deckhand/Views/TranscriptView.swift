import DeckhandKit
import SwiftUI

/// The conversation, pinned to its newest line, with anything you have said that has not come
/// back as a turn sitting below it.
///
/// Two lists on purpose. A turn is in the session's history; a queued line is in its inbox and
/// appears nowhere in the transcript until the session absorbs it — which is exactly why
/// speaking to a busy session and seeing nothing appear used to read as having sent nothing.
struct TranscriptView: View {
    @Bindable var model: AppModel
    let session: Session

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    if model.turns.isEmpty && queued.isEmpty { nothingYet }
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { index, turn in
                        // The id goes on the pair, not the card: a turn that is only a tool
                        // run has no card, and scrolling to the newest turn has to land on
                        // it anyway — silently it would not scroll at all.
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            // What it ran sits above what it said, in the order it happened.
                            if !turn.tools.isEmpty { ToolTrace(tools: turn.tools) }
                            if !turn.text.isEmpty {
                                TurnCard(turn: turn,
                                         showsRole: startsRun(index),
                                         waiting: index == unanswered ? awaiting : nil)
                            }
                        }
                        .id(index)
                    }
                    // Below everything the session has written down, because that is where
                    // they are: after the last thing it said, waiting to be read.
                    if !queued.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                            ForEach(queued) { item in
                                QueuedCard(
                                    item: item,
                                    // Nothing else will make it read this: the inbox is only
                                    // drained when a turn ends, so forcing it is ending the turn.
                                    force: item.isWaiting && session.isBusy
                                        ? { Task { await model.control(.cancel, of: session) } }
                                        : nil
                                )
                            }
                        }
                        .id("queued")
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.medium)
            }
            // Room at the end for the bar that floats over this: without it the newest line
            // lands behind the button, which is exactly the line you came to read.
            .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
            // Always the newest line. This once skipped the first load, to stop the summary
            // card at the top of the list being scrolled away before it could be read — the
            // summary has its own tab now, so the transcript can go back to doing the one
            // thing a transcript should do.
            .onChange(of: model.turns.count) { scroll(proxy) }
            .onChange(of: queued.count) { scroll(proxy) }
            .onAppear { scroll(proxy) }
        }
    }

    /// What you have said that the session has not picked up yet. Its own bookkeeping, read
    /// off the transcript by the Mac — never inferred from the shape of the conversation.
    private var queued: [Queued] { model.queued[session.sessionId] ?? [] }

    private var nothingYet: some View {
        Text(model.connection.isHealthy ? "Nothing said yet in this session" : "Waiting for the Mac…")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, Spacing.small)
    }

    /// The newest thing is always what you want to see, and what is still in the inbox is
    /// newer than anything the session has written down.
    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation {
            if queued.isEmpty {
                proxy.scrollTo(model.turns.count - 1, anchor: .bottom)
            } else {
                proxy.scrollTo("queued", anchor: .bottom)
            }
        }
    }

    /// False when the turn before this one was from the same speaker, so a run of replies
    /// carries one label rather than the same word over and over.
    private func startsRun(_ index: Int) -> Bool {
        index == 0 || model.turns[index - 1].role != model.turns[index].role
    }

    /// The last thing you said, when nothing has answered it yet.
    ///
    /// Your words used to sit at the foot of the transcript in grey, which read as "not sent";
    /// removing that left no way at all to tell a prompt still being worked on from one that
    /// has been dealt with. This marks the message itself instead of inventing a second one.
    private var unanswered: Int? {
        guard let mine = model.turns.lastIndex(where: \.isUser) else { return nil }
        let answered = model.turns[(mine + 1)...].contains { !$0.isUser && !$0.text.isEmpty }
        return answered ? nil : mine
    }

    /// Only while it is actually working. Anything it has not picked up at all is in the
    /// queue below, which says so itself — this is the other half: picked up, being worked on.
    private var awaiting: PillState? {
        session.isBusy ? .busy : nil
    }
}

/// The transcript exactly as Claude Code wrote it, newest at the end.
///
/// Everything else in this app is a reading of this file — turns, tool traces, the inbox replay
/// — so when one of those looks wrong, this is the only way to tell from a phone whether the app
/// is wrong or the session is. It opens at the bottom, which is where the news is.
struct RawView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var text: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(text ?? "Reading the transcript…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .padding(Spacing.small)
            }
            .defaultScrollAnchor(.bottom)
            .background(Palette.surfaceGround)
            .navigationTitle("\(session.name) raw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }.tint(Palette.tint)
                }
            }
        }
        .task { text = await model.raw(for: session) ?? "Nothing came back from the Mac" }
    }
}
