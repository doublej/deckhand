import DeckhandKit
import SwiftUI

/// One session: what it has been doing, what it said, and the control that talks back.
struct SessionView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var recorder = Recorder()

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar(connection: model.connection, status: model.status)
            summary
            transcript
            heard
            TalkControl(
                recorder: recorder,
                mode: model.preferences.talkMode,
                isMine: true,
                onStart: { model.status = "Recording for \(session.name)" },
                onClip: { await model.upload(clip: $0, to: session) },
                content: { isRecording, busy in
                    TalkBar(mode: model.preferences.talkMode, isRecording: isRecording, busy: busy)
                }
            )
        }
        .background(.black)
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Focus on Mac", systemImage: "macwindow") {
                    Task { await model.focus(session) }
                }
                .disabled(session.pane == nil)
            }
        }
        .task {
            model.turns = []
            await model.loadSummary(for: session)
            while !Task.isCancelled {
                await model.loadTurns(for: session)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    @ViewBuilder private var summary: some View {
        let text = model.summaries[session.sessionId]
        let working = model.summarising.contains(session.sessionId)
        if text != nil || working {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("since you last spoke")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    if working {
                        ProgressView().controlSize(.mini).tint(.white)
                    }
                }
                Text(text ?? "reading what it did…")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(text == nil ? Color.secondary : Color.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.04))
        }
    }

    @ViewBuilder private var heard: some View {
        if let heard = model.heard {
            Text(heard)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .textSelection(.enabled)
        }
    }

    /// Only the first turn of a run carries the name: repeating it reads as an interruption.
    private func startsRun(_ index: Int) -> Bool {
        index == 0 || model.turns[index - 1].role != model.turns[index].role
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if model.turns.isEmpty {
                        Text(model.connection.isHealthy
                            ? "Nothing said yet in this session"
                            : "Waiting for the Mac…")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { index, turn in
                        TurnBlock(turn: turn, compact: false, showsRole: startsRun(index)).id(index)
                    }
                }
                .padding(16)
            }
            .onChange(of: model.turns.count) {
                withAnimation { proxy.scrollTo(model.turns.count - 1, anchor: .bottom) }
            }
        }
    }
}

/// One round of conversation. The compact variant is what the landscape deck shows.
struct TurnBlock: View {
    let turn: Turn
    let compact: Bool
    /// False when the turn before this one was from the same speaker.
    let showsRole: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            if showsRole {
                Text(turn.isUser ? "you" : "claude")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(turn.isUser ? Color.white : Color.secondary)
            }
            Text(turn.text)
                .font(.system(size: compact ? 8 : 13, design: .monospaced))
                .foregroundStyle(turn.isUser ? .white : .white.opacity(0.75))
                .lineLimit(compact ? 14 : nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, turn.isUser ? 0 : 10)
        .overlay(alignment: .leading) {
            if !turn.isUser {
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
            }
        }
    }
}
