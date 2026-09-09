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
                                TurnCard(turn: turn, showsRole: startsRun(index))
                            }
                        }
                        .id(index)
                    }
                    // Everything above has happened; this is the line it has reached.
                    if session.isBusy { ActiveLine(doing: doing).id("active") }
                    if !queued.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                            ForEach(queued) { item in
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
            .onChange(of: session.isBusy) { scroll(proxy) }
            .onAppear { scroll(proxy) }
        }
    }

    /// What you have said that the session has not picked up yet, and only that. Its own
    /// bookkeeping, read off the transcript by the Mac — never inferred from the conversation.
    /// Anything it *has* picked up is a turn above, in the place it arrived.
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
            if !queued.isEmpty {
                proxy.scrollTo("queued", anchor: .bottom)
            } else if session.isBusy {
                proxy.scrollTo("active", anchor: .bottom)
            } else {
                proxy.scrollTo(model.turns.count - 1, anchor: .bottom)
            }
        }
    }

    /// False when the turn before this one was from the same speaker, so a run of replies
    /// carries one label rather than the same word over and over.
    private func startsRun(_ index: Int) -> Bool {
        index == 0 || model.turns[index - 1].role != model.turns[index].role
    }

    /// The newest thing the session ran, when it has run anything since it last spoke.
    ///
    /// A run still in flight comes back as a wordless trailing turn carrying what it has run so
    /// far, so the last tool of that turn is the step it is on. A turn with words is finished by
    /// definition, and then it is thinking rather than running.
    private var doing: Tool? {
        guard let last = model.turns.last, last.text.isEmpty else { return nil }
        return last.tools.last
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
    @Environment(\.accent) private var accent

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
                    Button("Close") { dismiss() }.tint(accent)
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
