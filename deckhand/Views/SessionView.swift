import DeckhandKit
import SwiftUI

/// One session as a page: who it is, what it has been doing, what it said, and the mark you
/// hold to answer. Light ground — the rail is the only dark surface in the language.
struct SessionView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var recorder = Recorder()
    @State private var showing: Pane = .summary
    @Environment(\.dismiss) private var dismiss

    /// Three things you want on arriving, and they want different layouts: the briefing wants
    /// a page to itself, the transcript wants to be pinned to its newest line, and the files
    /// are a list you scroll from the top.
    enum Pane: String, CaseIterable {
        case summary = "Summary", transcript = "Transcript", files = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch showing {
            case .summary: BriefingView(model: model, session: session)
            case .transcript: transcript
            case .files: FilesView(model: model, session: session)
            }
            // One slot, two things: the button you hold, or what it heard waiting to be sent.
            // Never both — while there is something to answer, that is the only thing the
            // foot of the page is for.
            if model.review[session.sessionId] != nil { review } else { talk }
            tabs
        }
        .animation(.snappy(duration: 0.22), value: model.review[session.sessionId])
        .background(Palette.surfaceGround)
        // No navigation bar. It was a whole band holding one chevron, stacked above a header
        // that already named the page — two rows of chrome before a word of content. The
        // chevron moved into the header and the band went with it.
        .toolbar(.hidden, for: .navigationBar)
        // Hiding the bar takes the system's swipe-back with it, so the page catches its own:
        // started at the leading edge, mostly sideways, and simultaneous so it never competes
        // with scrolling the transcript or opening a tool call.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onEnded { drag in
                    guard drag.startLocation.x < 28,
                          drag.translation.width > 80,
                          abs(drag.translation.height) < 80 else { return }
                    dismiss()
                }
        )
        // Anything waiting on you lives in the transcript, so do not leave it on a tab the
        // person is not looking at.
        .task {
            model.turns = []
            model.current = session.sessionId
            // Beside the transcript, not in front of it. The summariser thinks for ten
            // seconds or more, and awaiting it here left the page empty for that long —
            // then everything arrived at once and jumped to the newest turn.
            async let written: Void = model.loadSummary(for: session)
            while !Task.isCancelled {
                await model.loadTurns(for: session)
                try? await Task.sleep(for: .seconds(5))
            }
            await written
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.extraSmall) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.tint)
                    .frame(width: 28, height: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sessions")
            GlyphTile(DotGlyph.forName(session.name), size: 28, ground: Palette.lcdGround)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.name)
                    .font(Typography.pageTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.extraSmall)
            StatePill(session.isBusy ? .busy : .idle)
            Button {
                Task { await model.focus(session) }
            } label: {
                Image(systemName: "macwindow")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 34)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .tint(Palette.tint)
            .foregroundStyle(session.pane == nil ? Palette.textTertiary : Palette.tint)
            .disabled(session.pane == nil)
            .accessibilityLabel("Focus on Mac")
        }
        .padding(.leading, Spacing.extraSmall)
        .padding(.trailing, Spacing.small)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.extraSmall)
    }

    private var subtitle: String {
        let ago = session.lastActive.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        return "\(session.folder) · \(ago)"
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    if model.turns.isEmpty { nothingYet }
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
                            ForEach(Array(queued.enumerated()), id: \.offset) { _, text in
                                QueuedCard(text: text)
                            }
                        }
                        .id("queued")
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.medium)
            }
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
    private var queued: [String] { model.queued[session.sessionId] ?? [] }

    private var nothingYet: some View {
        Text(model.connection.isHealthy ? "Nothing said yet in this session" : "Waiting for the Mac…")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, Spacing.small)
    }

    /// At the foot of the page, not under the title. Up there it sat a few points beneath the
    /// folder and the timestamp and read as a third line of the same block; down here it is
    /// plainly a control, and the header goes back to being only the header.
    private var tabs: some View {
        HStack(spacing: Spacing.xxs) {
            ForEach(Pane.allCases, id: \.self) { pane in
                Button { showing = pane } label: { tab(pane) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab-\(pane.rawValue.lowercased())")
            }
            Spacer(minLength: 0)
            if model.summarising.contains(session.sessionId) { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.extraSmall)
        .overlay(alignment: .top) { Divider() }
    }

    /// The chosen one wears a pill, which is the word this language already uses for state.
    private func tab(_ pane: Pane) -> some View {
        let chosen = showing == pane
        return Text(pane.rawValue.uppercased())
            .font(Typography.eyebrow)
            .tracking(1)
            .foregroundStyle(chosen ? Palette.textPrimary : Palette.textTertiary)
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(chosen ? Palette.tint.opacity(0.18) : .clear)
            )
            .contentShape(.rect)
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
            content: { TalkMark(state: $0, level: recorder.level) }
        )
    }

    /// The newest thing is always what you want to see, and what you just said is newer than
    /// anything the session has written down.
    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation {
            if model.review[session.sessionId] != nil {
                proxy.scrollTo("review", anchor: .bottom)
            } else if !queued.isEmpty {
                proxy.scrollTo("queued", anchor: .bottom)
            } else {
                proxy.scrollTo(model.turns.count - 1, anchor: .bottom)
            }
        }
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
                send: { Task { await model.send(text, to: session) } },
                discard: { model.discard(for: session) }
            )
            .padding(Spacing.small)
            .frame(maxWidth: .infinity)
            .background(Palette.surfaceGround)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
    /// removing that left no way at all to tell a prompt still in the queue from one that has
    /// been dealt with. This marks the message itself instead of inventing a second one.
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
