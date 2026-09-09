import DeckhandKit
import SwiftUI

/// Landscape: every favourite as a column on the warm ground, transcripts in small type, and
/// holding a whole column talks to that session. Nothing to aim at — the column is the button.
struct DeckView: View {
    @Bindable var model: AppModel
    @State private var recorder = Recorder()
    @State private var active: String?

    /// Below this a column is a stripe, not a transcript. Past it the deck scrolls sideways.
    private static let minColumnWidth: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            head
            if model.deckSessions.isEmpty { placeholder } else { columns }
        }
        .background(Palette.lcdGround)
        .environment(\.colorScheme, .dark)
        .task {
            while !Task.isCancelled {
                await model.refreshSessions()
                await model.loadDeck()
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    private var head: some View {
        HStack(spacing: Spacing.small) {
            DotMark(DotGlyph.anchor, size: 24, tint: Palette.tint)
            Text(model.connection.label)
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            StatePill(model.connection.pill)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.extraSmall)
    }

    private var placeholder: some View {
        VStack {
            Spacer()
            Text("Star a session in portrait to put it on the deck")
                .font(Typography.railRow)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
        }
    }

    private var columns: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                deck(width: columnWidth(in: geo.size.width))
                    .frame(height: geo.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Share the width while the columns still fit; stop shrinking at the minimum and scroll.
    private func columnWidth(in total: CGFloat) -> CGFloat {
        let count = CGFloat(max(model.deckSessions.count, 1))
        return max(Self.minColumnWidth, (total - (count - 1)) / count)
    }

    private func deck(width: CGFloat) -> some View {
        HStack(spacing: 1) {
            ForEach(model.deckSessions) { session in
                column(for: session).frame(width: width)
            }
        }
    }

    private func startTalking(to session: Session) {
        active = session.sessionId
        model.status = "Recording for \(session.name)"
    }

    private func column(for session: Session) -> some View {
        TalkControl(
            recorder: recorder,
            mode: model.preferences.talkMode,
            isMine: active == session.sessionId,
            onStart: { startTalking(to: session) },
            onClip: { clip in
                await model.upload(clip: clip, to: session)
                active = nil
            },
            content: { state in
                Column(
                    session: session,
                    turns: model.deckTurns[session.sessionId] ?? [],
                    state: state,
                    review: model.review[session.sessionId],
                    send: { text in Task { await model.send(text, to: session) } },
                    discard: { model.discard(for: session) }
                ).accessibilityIdentifier("deck-column")
            }
        )
    }
}

/// One session's column: a rail row for a head, then as much of the conversation as fits.
private struct Column: View {
    let session: Session
    let turns: [Turn]
    let state: TalkState
    /// Held for reading, if this column is the one that just heard something.
    let review: String?
    let send: (String) -> Void
    let discard: () -> Void

    private var isRecording: Bool { state.isRecording }
    private var busy: Bool { state.busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    if turns.isEmpty {
                        Text("reading…")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                        DeckTurn(turn: turn, showsRole: index == 0 || turns[index - 1].role != turn.role)
                    }
                }
                .padding(Spacing.extraSmall)
            }
            .scrollDisabled(isRecording)
            if let review {
                ReviewCard(
                    text: review,
                    target: session.name,
                    send: { send(review) },
                    discard: discard,
                    compact: true
                )
                .padding(Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(isRecording ? 0.10 : 0.04))
        .overlay(alignment: .top) {
            if isRecording || busy {
                Rectangle().fill(Palette.recording).frame(height: 2)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.extraSmall) {
            GlyphTile(DotGlyph.forName(session.name), size: 20, prominent: isRecording)
            Text(session.name)
                .font(Typography.railRowSelected)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if state.canCancel {
                Button("CANCEL", action: state.cancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Palette.textSecondary)
            }
            StatePill(isRecording ? .rec : busy ? .wait : session.isBusy ? .busy : .idle)
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.06))
    }
}

/// A turn in a column: the same eyebrow the page uses, at deck size.
private struct DeckTurn: View {
    let turn: Turn
    let showsRole: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsRole {
                Text(turn.isUser ? "YOU" : "CLAUDE")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(turn.isUser ? Palette.tint : Palette.textTertiary)
            }
            Text(turn.text)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textPrimary.opacity(turn.isUser ? 1 : 0.75))
                .lineLimit(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
