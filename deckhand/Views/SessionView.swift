import DeckhandKit
import SwiftUI

/// One session: the last rounds it exchanged, and the button that talks back to it.
struct SessionView: View {
    @Bindable var model: AppModel
    let session: Session
    @State private var recorder = Recorder()

    var body: some View {
        VStack(spacing: 0) {
            transcript
            TalkButton(recorder: recorder, onClip: { clip in
                await model.upload(clip: clip, to: session)
            })
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
        .safeAreaInset(edge: .bottom) { StatusBar(text: model.status) }
        .task {
            model.turns = []
            while !Task.isCancelled {
                await model.loadTurns(for: session)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(model.turns.enumerated()), id: \.offset) { index, turn in
                        TurnBlock(turn: turn).id(index)
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

private struct TurnBlock: View {
    let turn: Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(turn.isUser ? "you" : "claude")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(turn.isUser ? .white : .secondary)
            Text(turn.text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(turn.isUser ? .white : .white.opacity(0.75))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, turn.isUser ? 0 : 12)
        .overlay(alignment: .leading) {
            if !turn.isUser {
                Rectangle().fill(.white.opacity(0.2)).frame(width: 1)
            }
        }
    }
}

/// Hold to record, release to send. No modes, no toggle to forget.
private struct TalkButton: View {
    @Bindable var recorder: Recorder
    let onClip: (URL) async -> Void
    @State private var busy = false

    var body: some View {
        Text(recorder.isRecording ? "RECORDING — RELEASE TO SEND" : busy ? "SENDING…" : "HOLD TO TALK")
            .font(.system(.footnote, design: .monospaced).weight(.semibold))
            .foregroundStyle(recorder.isRecording ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(recorder.isRecording ? .white : .white.opacity(0.12))
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !recorder.isRecording, !busy else { return }
                        Task { _ = await recorder.start() }
                    }
                    .onEnded { _ in
                        guard let clip = recorder.stop() else { return }
                        busy = true
                        Task {
                            await onClip(clip)
                            busy = false
                        }
                    }
            )
            .padding(16)
    }
}
