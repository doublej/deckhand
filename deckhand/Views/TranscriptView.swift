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
                    // Drawn as what they are: things you said. The session took them while it
                    // was working and Claude Code wrote them down nowhere, so this card is the
                    // only place they exist — but that is the app's problem, not yours, and a
                    // note explaining it on every one of them explained nothing.
                    ForEach(taken) { item in
                        TurnCard(turn: Turn(role: "user", text: item.text, timestamp: ""),
                                 showsRole: true,
                                 waiting: nil)
                    }
                    if !waiting.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                            ForEach(waiting) { item in
                                QueuedCard(
                                    text: item.text,
                                    // Nothing else will make it read this: the inbox is only
                                    // drained when a turn ends, so forcing it is ending the turn.
                                    force: session.isBusy
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
    /// Read by the session but written nowhere: these are part of the conversation and appear in
    /// no turn, which is the only reason they are shown at all.
    private var taken: [Queued] { queued.filter { !$0.isWaiting } }
    /// Still in the inbox. These are the ones that can be forced.
    private var waiting: [Queued] { queued.filter(\.isWaiting) }

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
            if waiting.isEmpty {
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
///
/// One `Text` per event, wrapped, in a lazy stack. It was one `Text` holding the whole file in a
/// scroll view free on both axes, which drew nothing at all: unwrapped, a line runs tens of
/// thousands of points wide and CoreText gives up and renders an empty view — a black screen with
/// no error anywhere. And it was the JSONL itself, which is mostly syntax: half a megabyte of
/// file came back as ten lines, nine of them punctuation. The Mac renders it now.
struct RawView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var lines: [String] = []
    @State private var read = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Palette.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    state
                }
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
        .task {
            lines = await model.raw(for: session) ?? []
            read = true
        }
    }

    /// Reading, or read and empty. Without this an empty file and a failed fetch both look
    /// exactly like the bug this view just had.
    @ViewBuilder private var state: some View {
        if !read {
            HStack(spacing: Spacing.extraSmall) {
                ProgressView()
                Text("Reading the transcript…")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.vertical, Spacing.large)
        } else if lines.isEmpty {
            Text("Nothing came back from the Mac")
                .font(Typography.subtitle)
                .foregroundStyle(Palette.textSecondary)
                .padding(.vertical, Spacing.large)
        } else {
            Text("\(lines.count) events, newest last")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, Spacing.small)
        }
    }
}
