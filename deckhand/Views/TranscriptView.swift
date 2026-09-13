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
    /// Whether there is an older page on the Mac. Owned by the page above, because it is the
    /// answer to the load the page above is already making every few seconds.
    @Binding var earlier: Bool
    /// Set while a step back is in flight, so a second tap does not ask for the same page twice.
    @State private var stepping = false
    /// The turn a hold has opened, and nil the rest of the time.
    @State private var held: Held?
    /// The subagent whose own transcript is open, and nil the rest of the time.
    @State private var reading: Agent?

    /// A turn on its way to the reader. Its own id rather than the turn's position, because the
    /// poll renumbers every row on a prepend and a sheet identified by a number that moves under
    /// it would re-present itself while somebody is reading.
    private struct Held: Identifiable {
        let id = UUID()
        let turn: Turn
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    if model.turns.isEmpty && queued.isEmpty { nothingYet }
                    earlierStep(proxy)
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { index, turn in
                        // The id goes on the pair, not the card: a turn that is only a tool
                        // run has no card, and scrolling to the newest turn has to land on
                        // it anyway — silently it would not scroll at all.
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            // What it ran sits above what it said, in the order it happened.
                            // Subagents come out of that row and get their own: one is a
                            // conversation that outlives the call which started it, and a dot
                            // cannot say "still going" or be opened.
                            let started = turn.tools.filter(\.isAgent)
                            let steps = turn.tools.filter { !$0.isAgent }
                            if !started.isEmpty {
                                AgentTrace(tools: started, agents: model.agents) { reading = $0 }
                            }
                            if !steps.isEmpty { ToolTrace(tools: steps) }
                            if !turn.text.isEmpty {
                                TurnCard(turn: turn,
                                         showsRole: startsRun(index),
                                         onHold: { held = Held(turn: turn) })
                            }
                        }
                        .id(index)
                    }
                    // Agents still going whose own row is off this page of the conversation.
                    // Above the working line rather than below it, because they started before
                    // the line was reached and are part of what the session is doing now.
                    if !loose.isEmpty { LooseAgents(agents: loose) { reading = $0 } }
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
            .fadingEdges()
            // Room at the end for the bar that floats over this: without it the newest line
            // lands behind the button, which is exactly the line you came to read.
            .contentMargins(.bottom, TalkMark.clearance, for: .scrollContent)
            // Always the newest line. This once skipped the first load, to stop the summary
            // card at the top of the list being scrolled away before it could be read — the
            // summary has its own tab now, so the transcript can go back to doing the one
            // thing a transcript should do.
            // The *newest* turn, not the count: reading further back grows the list at the far
            // end, and pinning to the bottom every time it grows is how a step back into the
            // conversation throws you straight out of it again.
            .onChange(of: model.turns.last?.timestamp) { scroll(proxy) }
            .onChange(of: queued.count) { scroll(proxy) }
            .onChange(of: session.isBusy) { scroll(proxy) }
            .onAppear { open(proxy) }
            // Held here rather than on the card: a sheet per row in a lazy stack is a sheet
            // that is torn down the moment the row it hangs off scrolls out of the list.
            .sheet(item: $held) { TurnReader(turn: $0.turn) }
            .sheet(item: $reading) { AgentView(model: model, session: session, agent: $0) }
        }
    }

    /// The agents still going that no turn on this page started, so a person can see several at
    /// once and reach any of them. The arithmetic is in `DeckhandKit`, where a test can reach it.
    private var loose: [Agent] { Agent.loose(Array(model.agents.values), notIn: model.turns) }

    /// What you have said that the session has not picked up yet, and only that. Its own
    /// bookkeeping, read off the transcript by the Mac — never inferred from the conversation.
    /// Anything it *has* picked up is a turn above, in the place it arrived.
    private var queued: [Queued] { model.queued[session.sessionId] ?? [] }

    /// The way back into the rest of the conversation, and only when there is one — a control
    /// that answers "nothing older" after a wait is worse than no control at all.
    ///
    /// Nothing is held on the phone between launches and nothing needs to be: the Mac has the
    /// transcript and does the parsing, so this is a request for a page rather than a cache.
    @ViewBuilder private func earlierStep(_ proxy: ScrollViewProxy) -> some View {
        if earlier {
            Button { step(proxy) } label: {
                HStack(spacing: Spacing.xxs) {
                    if stepping { ProgressView().controlSize(.mini) }
                    Text(stepping ? "Reading…" : "Earlier")
                }
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.small)
            }
            .disabled(stepping)
        }
    }

    private func step(_ proxy: ScrollViewProxy) {
        guard !stepping else { return }
        stepping = true
        Task {
            let (added, more) = await model.loadOlderTurns(for: session)
            earlier = more
            // Every row on screen has just been pushed down by exactly this many, and the ids
            // are positions, so the turn that was at the top is now at `added`. One hop first:
            // the rows have to be renumbered before one of them can be asked for by number.
            try? await Task.sleep(for: .milliseconds(1))
            if added > 0 { proxy.scrollTo(added, anchor: .top) }
            stepping = false
        }
    }

    private var nothingYet: some View {
        Text(model.connection.isHealthy ? "Nothing said yet in this session" : "Waiting for the Mac…")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, Spacing.small)
    }

    /// The newest thing is always what you want to see, and what is still in the inbox is
    /// newer than anything the session has written down.
    private func scroll(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let jump = {
            if !queued.isEmpty {
                proxy.scrollTo("queued", anchor: .bottom)
            } else if session.isBusy {
                proxy.scrollTo("active", anchor: .bottom)
            } else {
                proxy.scrollTo(model.turns.count - 1, anchor: .bottom)
            }
        }
        if animated { withAnimation { jump() } } else { jump() }
    }

    /// The opening jump, made again once the rows it skipped over have been measured.
    ///
    /// A `LazyVStack` knows its rows' identities and not their heights, so the offset a
    /// `scrollTo` lands on is however many rows have actually been laid out plus a guess for the
    /// rest — and this transcript's rows run from a 20pt tool trace to a 2000pt turn, so the
    /// guess is never close. Measured on one session's twenty-five turns over six cold opens,
    /// the scroll view's own idea of its content came back as anything between 18,216 and 25,036
    /// points. Aim at the high end of that and the open lands past the end of the conversation:
    /// a page that looks empty with the transcript sitting above it, and the space below it
    /// disappears the moment scrolling back measures the rows for real.
    ///
    /// So it is aimed again, twice, after the layout has been round. Not animated on the way in:
    /// a glide over twenty thousand points is realising rows the whole way down, which is the
    /// same guess made continuously and a transcript flying past on every open.
    private func open(_ proxy: ScrollViewProxy) {
        scroll(proxy, animated: false)
        Task {
            for _ in 0..<2 {
                try? await Task.sleep(for: .milliseconds(50))
                scroll(proxy, animated: false)
            }
        }
    }

    /// False when the turn before this one was from the same speaker, so a run of replies
    /// carries one label rather than the same word over and over.
    private func startsRun(_ index: Int) -> Bool {
        index == 0 || model.turns[index - 1].speaker() != model.turns[index].speaker()
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
                    // Teal on purpose, not an oversight: a sheet is its own surface and
                    // the talk mark is behind it. Same rule as `AssetView` and
                    // `SessionFilters` — only the page you are dictating into goes orange.
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
