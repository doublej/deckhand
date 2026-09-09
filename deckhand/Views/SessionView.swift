import DeckhandKit
import SwiftUI

/// One session as a page: who it is, what it has been doing, what it said, and the mark you
/// hold to answer. Light ground — the rail is the only dark surface in the language.
struct SessionView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var recorder = Recorder()

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            talk
        }
        .background(Palette.surfaceGround)
        // The bar stays, emptied: the page names itself, but a phone still needs its back
        // button and there is nowhere honest to put a second one.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Focus on Mac", systemImage: "macwindow") {
                    Task { await model.focus(session) }
                }
                .disabled(session.pane == nil)
                .tint(Palette.tint)
            }
        }
        .task {
            model.turns = []
            model.current = session.sessionId
            await model.loadSummary(for: session)
            while !Task.isCancelled {
                await model.loadTurns(for: session)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var header: some View {
        PageHeader(
            glyph: DotGlyph.forName(session.name),
            title: session.name,
            subtitle: subtitle
        ) {
            StatePill(session.isBusy ? .busy : .idle)
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.small)
    }

    private var subtitle: String {
        let ago = session.lastActive.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        return "\(session.folder) · \(ago)"
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    summary
                    if model.turns.isEmpty { nothingYet }
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { index, turn in
                        TurnCard(turn: turn, showsRole: startsRun(index)).id(index)
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.medium)
            }
            .onChange(of: model.turns.count) {
                withAnimation { proxy.scrollTo(model.turns.count - 1, anchor: .bottom) }
            }
        }
    }

    private var nothingYet: some View {
        Text(model.connection.isHealthy ? "Nothing said yet in this session" : "Waiting for the Mac…")
            .font(Typography.subtitle)
            .foregroundStyle(Palette.textSecondary)
            .padding(.vertical, Spacing.small)
    }

    /// What it did while you were away. Absent until there is something to say about it.
    @ViewBuilder private var summary: some View {
        let text = model.summaries[session.sessionId]
        let working = model.summarising.contains(session.sessionId)
        if text != nil || working {
            Card(spacing: Spacing.xxs) {
                HStack(spacing: Spacing.extraSmall) {
                    Text("SINCE YOU LAST SPOKE")
                        .font(Typography.eyebrow)
                        .tracking(1)
                        .foregroundStyle(Palette.textTertiary)
                    if working { ProgressView().controlSize(.mini) }
                }
                Text(text ?? "reading what it did…")
                    .font(Typography.subtitle)
                    .foregroundStyle(text == nil ? Palette.textSecondary : Palette.textPrimary)
            }
        }
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
            content: { isRecording, busy in
                TalkMark(mode: model.preferences.talkMode, isRecording: isRecording, busy: busy,
                         level: recorder.level, heard: model.heard)
            }
        )
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
