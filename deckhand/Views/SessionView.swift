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
    @State private var wantedName = ""
    @Environment(\.dismiss) private var dismiss

    /// Three things you want on arriving, and they want different layouts: the briefing wants
    /// a page to itself, the transcript wants to be pinned to its newest line, and the files
    /// are a list you scroll from the top.
    enum Pane: String, CaseIterable {
        case summary = "Summary", transcript = "Transcript", files = "Files"
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

    var body: some View {
        VStack(spacing: 0) {
            header
            fullness
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
        .sheet(isPresented: $filtering) { SessionFilters(model: model, session: session) }
        // A name is the one thing here you type rather than press, and it is short enough that
        // a whole screen for it would be more ceremony than the thing deserves.
        .alert("Rename \(session.name)", isPresented: $renaming) {
            TextField("Name", text: $wantedName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Rename") { Task { await model.rename(session, to: wantedName) } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Runs Claude Code's own /rename in its pane on the Mac.")
        }
        .confirmationDialog(
            "Clear \(session.name)?",
            isPresented: .init(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            Button("Clear the conversation", role: .destructive) {
                if let confirming { send(confirming) }
                confirming = nil
            }
            Button("Keep it", role: .cancel) { confirming = nil }
        } message: {
            Text("Everything said in this session goes. There is no undo.")
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
                await model.loadTurns(for: session)
                try? await Task.sleep(for: .seconds(5))
            }
            await written
        }
    }

    @ViewBuilder private var pane: some View {
        switch showing {
        case .summary: BriefingView(model: model, session: session)
        case .transcript: TranscriptView(model: model, session: session)
        case .files: FilesView(model: model, session: session)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.extraSmall) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
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
            StateWord(session.isBusy ? .busy : .idle)
            controls
        }
        .padding(.leading, Spacing.extraSmall)
        .padding(.trailing, Spacing.small)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.extraSmall)
    }

    /// Everything you can do to the session rather than say to it, behind one glyph: bringing
    /// its pane forward, stopping a run, compacting, clearing. A row of four buttons up here
    /// would be more chrome than the header has, and three of the four are rare.
    ///
    /// All of them are keystrokes in its pane, so all of them need one — without a pane the
    /// menu is there and says why rather than quietly doing nothing.
    private var controls: some View {
        Menu {
            Button("Show on the Mac", systemImage: "display") {
                Task { await model.focus(session) }
            }
            .disabled(hasNoPane)
            Button("Rename…", systemImage: "text.cursor") {
                wantedName = session.name
                renaming = true
            }
            .disabled(hasNoPane)
            // What the Mac does to words on their way into this session — this session's own
            // setting rather than the Mac's, because what you want done to words going into one
            // project is not what you want done to words going into another.
            Button("Words on the way in…", systemImage: "line.3.horizontal.decrease") {
                filtering = true
            }
            // Always reachable, not only when something looks wrong: every other view here is
            // a reading of that file, and this is the file.
            Button("Raw transcript", systemImage: "scroll") { reading = true }
            // For prompts that outlived the session that was going to read them: a session
            // killed mid-queue leaves its enqueues with nothing to remove them.
            Button("Clear queued prompts", systemImage: "tray.and.arrow.up") {
                Task { await model.clearQueue(for: session) }
            }
            .disabled((model.queued[session.sessionId] ?? []).isEmpty)
            Divider()
            ForEach(Control.allCases, id: \.self) { action in
                Button(action.label, systemImage: action.symbol, role: role(action)) {
                    if action.asksFirst { confirming = action } else { send(action) }
                }
                .disabled(hasNoPane)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 28, height: 34)
                .contentShape(.rect)
        }
        .tint(accent)
        .foregroundStyle(accent)
        .accessibilityLabel("Session controls")
    }

    /// Whether the things in that menu which are keystrokes can work at all.
    ///
    /// It used to switch off the whole menu, which was right while every item in it was a
    /// keystroke. Two of them never were — reading the transcript is a file on disk, clearing the
    /// queue is a file the daemon writes — and the filter chain is a third. With iTerm unreachable
    /// the menu was the only way to any of those, and the menu was the thing switched off.
    private var hasNoPane: Bool { session.pane == nil }

    private func role(_ action: Control) -> ButtonRole? {
        action == .clear ? .destructive : nil
    }

    private func send(_ action: Control) {
        Task { await model.control(action, of: session) }
    }

    /// How much of the window this session has left, on every tab: it is the one number that
    /// changes what you would do next — compact it now, or carry on.
    @ViewBuilder private var fullness: some View {
        if let context = session.context {
            HStack(spacing: Spacing.extraSmall) {
                Meter(context.share, tint: Palette.pressure(context.pressure), thickness: 3)
                Text(context.line)
                    .font(Typography.hint)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.small)
        }
    }

    private var subtitle: String {
        let ago = session.lastActive.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        return "\(session.folder) · \(ago)"
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
