import DeckhandKit
import SwiftUI

/// One session as a page: who it is, what it has been doing, what it said, and the mark you
/// hold to answer. Light ground — the rail is the only dark surface in the language.
struct SessionView: View {
    @Bindable var model: AppModel
    /// Which session this page is. Identity only — everything else is read from the listing,
    /// which is still refreshing behind this page.
    let opened: Session
    @State private var recorder = Recorder()
    @State private var showing: Pane = .summary
    /// Set while the one control that cannot be undone waits to be confirmed.
    @State private var confirming: Control?
    @State private var renaming = false
    @State private var reading = false
    @State private var filtering = false
    @State private var configuring = false
    /// Whether the Mac holds turns older than the ones on screen. Answered by every load, so
    /// the transcript can offer the way back without a request of its own to find out.
    @State private var earlier = false
    @Environment(\.dismiss) private var dismiss

    /// What the confirmation is about to do, in that control's own words.
    private var asking: Caution? { confirming?.caution(about: session.name) }

    /// Four things you want on arriving, and they want different layouts: the briefing wants
    /// a page to itself, the transcript wants to be pinned to its newest line, and the files and
    /// the slips this session put on the phone are lists you scroll from the top.
    enum Pane: String, CaseIterable {
        case summary = "Summary", slips = "Slips", transcript = "Transcript", files = "Files"
    }

    /// The session as the Mac last described it, not as it was when the page opened. A compact,
    /// a rename or a run starting all happen while you are looking at this, and the figures
    /// under the header were frozen at whatever they said on arrival.
    private var session: Session {
        model.sessions.first { $0.sessionId == opened.sessionId } ?? opened
    }

    /// What this page's accents are drawn in. Read here rather than from the environment because
    /// this is the view that puts it there, and a view never sees what it hands its own children.
    private var accent: Color { Palette.accent(recording: recorder.isRecording) }

    /// What this page lends its sheets so a field on one can be spoken into: the page's own
    /// recorder, never one of theirs. A sheet that made its own would record while this page stayed
    /// teal, and a sheet rebuilt mid-clip — which a rotation is — would drop it.
    private var say: Dictation {
        Dictation(recorder: recorder, mode: model.preferences.talkMode) {
            await model.dictated($0, for: session)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionHead(model: model,
                        session: session,
                        confirming: $confirming,
                        renaming: $renaming,
                        reading: $reading,
                        filtering: $filtering,
                        configuring: $configuring)
            pane
                // Over the content, not under it. Stacked below, the bar took a band off every
                // tab to offer one button; floating, it costs the page nothing and the panes
                // add its height to the end of their own content so anything can be read out
                // from under it.
                .overlay(alignment: .bottom) {
                    SessionFoot(model: model, session: session, recorder: recorder)
                }
            tabs
        }
        .animation(.snappy(duration: 0.22), value: model.review[session.sessionId])
        // The whole page goes utt orange while the mark at its foot is open, not only the mark:
        // one decision, made here, that every accent inside the page reads out of the
        // environment. It is the recorder's own state, so the page is teal again the instant the
        // clip is sent, thrown away, refused or interrupted.
        .accent(accent)
        .background(Palette.surfaceGround)
        // No navigation bar. It was a whole band holding one chevron, stacked above a header
        // that already named the page — two rows of chrome before a word of content. The
        // chevron moved into the header and the band went with it.
        .toolbar(.hidden, for: .navigationBar)
        .modifier(LocalLinks(mac: model.macAddress, paired: model.settings.host))
        .sheet(isPresented: $reading) { RawView(model: model, session: session) }
        .sheet(isPresented: $filtering) {
            SessionFilters(model: model, session: session, say: say)
        }
        // Built here rather than looked up in the picker's catalog: that page wants a path and a
        // name, this session has both, and a folder with no atlas record is still a folder whose
        // settings someone may want to change.
        .sheet(isPresented: $configuring) {
            ProjectSettingsView(model: model,
                                project: Project(name: session.folder, path: session.cwd))
        }
        // A sheet rather than the alert this was, because an alert holds a field and buttons and
        // nothing in between — and what a name needs beside it is the mark. See `Renaming`.
        .sheet(isPresented: $renaming) {
            Renaming(session: session, say: say) { wanted in
                Task { await model.rename(session, to: wanted) }
            }
        }
        // One dialog for every control that cannot be undone, and it says whatever that control
        // says. It used to be written for `clear` alone, so adding `exit` to the menu would have
        // asked "Clear this?" before quitting Claude Code.
        .confirmationDialog(
            asking?.title ?? "",
            isPresented: .init(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button(asking?.verb ?? "", role: .destructive) {
                // The model directly rather than a helper: the one in `SessionHead` is
                // for its menu, and a second copy here would be the same three lines
                // twice. `send` unqualified is the C syscall, which compiles.
                if let confirming { Task { await model.control(confirming, of: session) } }
                confirming = nil
            }
            Button("Keep it", role: .cancel) { confirming = nil }
        } message: {
            Text(asking?.because ?? "")
        }
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
                // As many as are already on screen, not a fixed page: this poll used to replace
                // the list with the newest eight every five seconds, so anything scrolled back to
                // was taken away again before it could be read.
                earlier = await model.loadTurns(for: session, limit: model.shown)
                try? await Task.sleep(for: .seconds(5))
            }
            await written
        }
    }

    @ViewBuilder private var pane: some View {
        switch showing {
        case .summary: BriefingView(model: model, session: session)
        case .transcript: TranscriptView(model: model, session: session, earlier: $earlier)
        case .files: FilesView(model: model, session: session)
        case .slips: ArtifactsView(model: model, session: session)
        }
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
                Capsule().fill(chosen ? accent.opacity(0.18) : .clear)
            )
            .contentShape(.rect)
    }

}
