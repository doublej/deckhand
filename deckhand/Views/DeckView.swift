import DeckhandKit
import SwiftUI

/// Landscape: every favourite as a column, transcripts in small type, and holding a whole
/// column talks to that session. Nothing to aim at — the column is the button.
struct DeckView: View {
    @Bindable var model: AppModel
    @State private var recorder = Recorder()
    @State private var active: String?

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar(connection: model.connection, status: model.status)
            if model.deckSessions.isEmpty {
                Spacer()
                Text("Star a session in portrait to put it on the deck")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                columns
            }
        }
        .background(.black)
        .task {
            while !Task.isCancelled {
                await model.refreshSessions()
                await model.loadDeck()
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    private var columns: some View {
        HStack(spacing: 1) {
            ForEach(model.deckSessions) { session in
                TalkControl(
                    recorder: recorder,
                    mode: model.preferences.talkMode,
                    isMine: active == session.sessionId,
                    onStart: {
                        active = session.sessionId
                        model.status = "Recording for \(session.name)"
                    },
                    onClip: { clip in
                        await model.upload(clip: clip, to: session)
                        active = nil
                    },
                    content: { isRecording, busy in
                        Column(
                            session: session,
                            turns: model.deckTurns[session.sessionId] ?? [],
                            isRecording: isRecording,
                            busy: busy
                        )
                        .accessibilityIdentifier("deck-column")
                    }
                )
            }
        }
    }
}

/// One session's column: who it is, then as much of the conversation as fits, tiny.
private struct Column: View {
    let session: Session
    let turns: [Turn]
    let isRecording: Bool
    let busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if turns.isEmpty {
                        Text("reading…")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                        TurnBlock(
                            turn: turn,
                            compact: true,
                            showsRole: index == 0 || turns[index - 1].role != turn.role
                        )
                    }
                }
                .padding(8)
            }
            .scrollDisabled(isRecording)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isRecording ? .white.opacity(0.16) : .white.opacity(0.04))
        .overlay(alignment: .top) {
            if isRecording || busy {
                Rectangle().fill(.white).frame(height: 2)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(session.isBusy ? .white : .white.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(session.name)
                .font(.system(size: 10, design: .monospaced).weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(busy ? "sending" : isRecording ? "listening" : session.folder)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.06))
    }
}
