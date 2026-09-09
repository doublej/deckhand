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

    /// Two things you want on arriving, and they want opposite layouts: the briefing wants a
    /// page to itself, the transcript wants to be pinned to its newest line.
    enum Pane: String, CaseIterable { case summary = "Summary", transcript = "Transcript" }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs
            switch showing {
            case .summary: briefing
            case .transcript: transcript
            }
            // One slot, two things: the button you hold, or what it heard waiting to be sent.
            // Never both — while there is something to answer, that is the only thing the
            // foot of the page is for.
            if model.review[session.sessionId] != nil { review } else { talk }
        }
        .animation(.snappy(duration: 0.22), value: model.review[session.sessionId])
        .background(Palette.surfaceGround)
        // No navigation bar. It was a whole band holding one chevron, stacked above a header
        // that already named the page — two rows of chrome before a word of content. The
        // chevron moved into the header and the band went with it. Swiping back still works.
        .toolbar(.hidden, for: .navigationBar)
        // Anything waiting on you lives in the transcript, so do not leave it on a tab the
        // person is not looking at.
        .onChange(of: model.pending[session.sessionId]) { showing = .transcript }
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
                        TurnCard(turn: turn, showsRole: startsRun(index)).id(index)
                    }
                    pending
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.medium)
            }
            // Always the newest line. This once skipped the first load, to stop the summary
            // card at the top of the list being scrolled away before it could be read — the
            // summary has its own tab now, so the transcript can go back to doing the one
            // thing a transcript should do.
            .onChange(of: model.turns.count) { scroll(proxy) }
            .onAppear { scroll(proxy) }
            .onChange(of: model.pending[session.sessionId]) { scroll(proxy) }
        }
    }

    private var nothingYet: some View {
        Text(model.connection.isHealthy ? "Nothing said yet in this session" : "Waiting for the Mac…")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, Spacing.small)
    }

    private var tabs: some View {
        HStack(spacing: Spacing.medium) {
            ForEach(Pane.allCases, id: \.self) { pane in
                Button { showing = pane } label: { tab(pane) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab-\(pane.rawValue.lowercased())")
            }
            Spacer(minLength: 0)
            if model.summarising.contains(session.sessionId) { ProgressView().controlSize(.mini) }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.extraSmall)
    }

    private func tab(_ pane: Pane) -> some View {
        let chosen = showing == pane
        return VStack(spacing: Spacing.xxs) {
            Text(pane.rawValue.uppercased())
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(chosen ? Palette.textPrimary : Palette.textTertiary)
            // The rule carries the state rather than a filled capsule: this sits directly
            // under the page header and a second solid shape there fights it. It is sized to
            // the word rather than to the space, which is the difference between a tab and
            // something that reads as a progress bar.
            Capsule()
                .fill(chosen ? Palette.tint : .clear)
                .frame(height: 2)
        }
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(.rect)
    }

    /// What it did while you were away, with the whole page to say it in.
    private var briefing: some View {
        ScrollView {
            Group {
                if let text = model.summaries[session.sessionId] {
                    Prose(text)
                } else {
                    Text(model.summarising.contains(session.sessionId)
                         ? "Reading what it did…"
                         : "Nothing yet")
                        .font(Typography.subtitle)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.medium)
        }
        .frame(maxHeight: .infinity)
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
            } else if model.pending[session.sessionId] != nil {
                proxy.scrollTo("pending", anchor: .bottom)
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

    /// What you just said, sitting where it will sit once the session has written it down.
    /// Dimmed until then, so "sent" and "arrived" are not drawn as the same thing.
    @ViewBuilder private var pending: some View {
        if let text = model.pending[session.sessionId] {
            TurnCard(
                turn: Turn(role: "user", text: text, timestamp: ""),
                showsRole: model.turns.last?.isUser != true
            )
            .opacity(0.55)
            .id("pending")
        }
    }

    /// Only the first turn of a run carries the name: repeating it reads as an interruption.
    private func startsRun(_ index: Int) -> Bool {
        index == 0 || model.turns[index - 1].role != model.turns[index].role
    }
}

/// One round of conversation, as a card with a mono eyebrow.
struct TurnCard: View {
    let turn: Turn
    /// False when the turn before this one was from the same speaker.
    let showsRole: Bool

    var body: some View {
        Card(spacing: Spacing.xxs) {
            if showsRole {
                Text(turn.isUser ? "YOU" : "CLAUDE")
                    .font(Typography.eyebrow)
                    .tracking(1)
                    .foregroundStyle(turn.isUser ? Palette.tint : Palette.textTertiary)
            }
            Text(turn.text)
                .font(.system(size: 13))
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
        }
    }
}
