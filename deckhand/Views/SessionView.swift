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
    /// The pane just swiped to, while its name is still worth saying. Nil the rest of the time,
    /// which is nearly all of it — see `landing`.
    @State private var landed: Pane?
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
                        configuring: $configuring,
                        pages: Pane.allCases.count,
                        lit: Pane.allCases.firstIndex(of: showing) ?? 0,
                        working: model.summarising.contains(session.sessionId))
            pane
                // Over the content, not under it. Stacked below, the bar took a band off every
                // tab to offer one button; floating, it costs the page nothing and the panes
                // add its height to the end of their own content so anything can be read out
                // from under it. And it reaches the foot of the screen now that the tab bar
                // that used to sit under it is gone.
                .overlay(alignment: .bottom) {
                    SessionFoot(model: model, session: session, recorder: recorder)
                }
                .overlay(alignment: .top) { landing }
        }
        // Named on arrival and then gone. The dots say where you are among four; they cannot say
        // which four, and a pane you land on by accident is a pane you have to read to identify.
        .onChange(of: showing) { _, now in
            withAnimation(.snappy(duration: 0.2)) { landed = now }
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                guard showing == now else { return }
                withAnimation(.easeOut(duration: 0.35)) { landed = nil }
            }
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
                    // Only from the first pane. The panes are swiped between now, so a drag from
                    // the left edge on any other one means "back a pane" and the page takes it —
                    // catching it here as well would page and dismiss on the same gesture. From
                    // the first there is nothing to its left, so leaving is what it can only mean.
                    guard showing == Pane.allCases.first,
                          drag.startLocation.x < 28,
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

    /// The name of the pane you just landed on, for as long as it takes to read it.
    ///
    /// Subtle on purpose and never in the way: it is not a control, it does not take the touch,
    /// and it leaves on its own after a second. A label that stayed would be the tab bar again
    /// by another name — this exists only because a swipe can be accidental and the four dots
    /// say how many panes there are without saying which one this is.
    @ViewBuilder private var landing: some View {
        if let landed {
            Text(landed.rawValue.uppercased())
                .font(Typography.eyebrow)
                .tracking(1.5)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                )
                .padding(.top, Spacing.extraSmall)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// The four panes side by side, swiped between rather than chosen from a bar.
    ///
    /// The bar is gone and nothing replaced it at the foot: it was a band of chrome across every
    /// screen to hold four words, and the four words are now four dots on a row the header was
    /// already drawing. That is the whole saving — the panes are a tab bar's height taller and
    /// the mark you hold to talk sits where the bar was.
    ///
    /// Its own index display is off. The native dots would land exactly where the mark floats,
    /// which is the one place on this page something must not be drawn.
    private var pane: some View {
        TabView(selection: $showing) {
            BriefingView(model: model, session: session).tag(Pane.summary)
            ArtifactsView(model: model, session: session).tag(Pane.slips)
            TranscriptView(model: model, session: session, earlier: $earlier).tag(Pane.transcript)
            FilesView(model: model, session: session).tag(Pane.files)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.snappy(duration: 0.25), value: showing)
    }

}
