import DeckhandKit
import SwiftUI

/// The manager panel: the rail, one swipe further left.
///
/// Everything else in this app speaks to a session. This speaks to the manager — one Claude
/// session running inside the daemon that can read every session on the Mac, speak into them,
/// set their standing orders, start new ones, change this Mac's switches, and move this phone's
/// own screen. What it may *not* do is the load-bearing half and it is written down in the
/// daemon's `manager/doing.py`: it never types into a pane, so it cannot stop, clear or rename a
/// session, answer a slip, or edit a filter chain. Those are the person's, and they are here.
///
/// The rail surface, because it is reached from the rail and it is a list of things happening on
/// the Mac. Two halves under one foot: the **tray** (`TrayView`), every session that needs you
/// with its slips answerable in place, and the **manager**, whose conversation is bubbles — the
/// person's trailing and the manager's leading, see `ManagerBubble` — with everything it *did* as
/// a line rather than a bubble. Saying something to the manager turns to its half.
struct ManagerView: View {
    @Bindable var model: AppModel
    @State private var recorder = Recorder()
    @State private var clearing = false
    @FocusState private var typing: Bool
    @Environment(\.scenePhase) private var phase

    private var desk: ManagerDesk { model.manager }
    private var accent: Color { Palette.accent(recording: recorder.isRecording) }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            switch desk.tab {
            case .tray: TrayView(model: model)
            case .manager: conversation
            }
            foot
        }
        .padding(.horizontal, Spacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.lcdGround.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accent(accent)
        // Keyed on `working` as well, so a send restarts the loop at the fast pace at once rather
        // than after whatever is left of a four-second rest.
        .task(id: [desk.open, desk.working]) { await poll() }
        .onChange(of: desk.open) { _, now in
            if !now {
                typing = false
                Task { await model.leaveManager() }
            }
        }
        // Leaving the app is leaving the panel, and it is the case notifications exist for.
        .onChange(of: phase) { _, now in
            if now != .active, desk.open { Task { await model.leaveManager() } }
        }
    }

    /// The two halves, as two words. The one showing is bright; the manager's goes the accent
    /// when it has said something you have not read, which is the only way a reply landing behind
    /// the tray is noticed.
    private var tabs: some View {
        HStack(spacing: Spacing.medium) {
            tab("TRAY", .tray, count: desk.tray.waitingCount, unread: false)
            tab("MANAGER", .manager, count: 0,
                unread: (desk.entries.last?.id ?? 0) > desk.readEntry || desk.working)
        }
        .padding(.top, Spacing.extraSmall)
        .onChange(of: desk.entries.last?.id) { _, last in
            if desk.tab == .manager { desk.readEntry = last ?? 0 }
        }
        .onChange(of: desk.tab) { _, now in
            if now == .manager { desk.readEntry = desk.entries.last?.id ?? 0 }
        }
    }

    private func tab(_ word: String, _ which: ManagerTab, count: Int, unread: Bool) -> some View {
        Button { desk.tab = which } label: {
            HStack(spacing: Spacing.xxs) {
                Text(word)
                if count > 0 { Text("\(count)").foregroundStyle(Palette.lcdYellow) }
            }
            .font(Typography.eyebrow)
            .tracking(2)
            .foregroundStyle(desk.tab == which ? Palette.textPrimary
                             : unread ? accent : Palette.textTertiary)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(which == .tray ? "manager-tab-tray" : "manager-tab-manager")
    }

    /// Everything said, oldest first, with the working line after it when the Mac is still going.
    private var conversation: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    if desk.entries.isEmpty { opening }
                    ForEach(desk.entries) { entry in
                        ManagerLine(entry: entry)
                            // On the wrapper rather than on the card: an act draws no card, and
                            // a scroll-to that lands on one would silently do nothing.
                            .id(entry.id)
                    }
                    // Drawn ahead of the Mac: the words are on screen the moment they are sent,
                    // dimmed until the Mac has written them down.
                    ForEach(Array(desk.pending.enumerated()), id: \.offset) { _, words in
                        ManagerBubble(text: words, mine: true).opacity(0.55)
                    }
                    if desk.hearing {
                        Text("Hearing…")
                            .font(Typography.hint)
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.horizontal, Spacing.extraSmall)
                    }
                    // The sentence being written, as far as it has got. Replaced by its entry
                    // when the block is done, on the same poll.
                    if !desk.partial.isEmpty {
                        ManagerBubble(text: desk.partial, mine: false).id("partial")
                    }
                    if desk.working {
                        ActiveLine(doing: desk.doing.isEmpty ? nil
                                       : Tool(name: desk.doing, detail: ""))
                            .padding(.top, Spacing.xxs)
                            .id("working")
                    }
                    if let failure = desk.failure {
                        Text(failure)
                            .font(Typography.hint)
                            .foregroundStyle(Palette.lcdRed)
                            .padding(.horizontal, Spacing.extraSmall)
                    }
                }
                .padding(.top, Spacing.large)
                .padding(.bottom, Spacing.small)
            }
            .scrollIndicators(.hidden)
            .fadingEdges()
            // The newest id, never the count: the panel grows at the end and only at the end,
            // and pinning to the bottom on a count change would fight a person reading back.
            .onChange(of: desk.entries.last?.id) { _, _ in bottom(scroller) }
            .onChange(of: desk.working) { _, _ in bottom(scroller) }
            .onChange(of: desk.pending.count) { _, _ in bottom(scroller) }
            .onChange(of: desk.partial) { _, _ in bottom(scroller) }
            .onAppear { bottom(scroller) }
        }
    }

    /// What the panel says before anybody has said anything to it. The one place on this screen
    /// that explains itself, because a screen with nothing on it explains nothing.
    private var opening: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            Text("THE MANAGER")
                .font(Typography.eyebrow)
                .tracking(1)
                .foregroundStyle(Palette.textTertiary)
            Text("Ask about anything running on the Mac, or tell it what to do about one. "
                 + "It can read every session, speak into them, set their standing orders, "
                 + "start new ones and move this screen. It cannot stop, clear or rename a "
                 + "session, answer a slip, or change a filter chain — those are yours.")
                .font(Typography.prose)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.extraSmall)
        .padding(.bottom, Spacing.small)
    }

    /// The one line you write on, and the mark under it. Both send to the same place, so unlike
    /// the orders pane there is no second meaning to keep them apart — a clip goes to the
    /// manager and so does the field.
    @ViewBuilder private var foot: some View {
        if let heard = desk.review {
            ReviewCard(text: heard, target: "the manager",
                       send: { edited in Task { await model.sendReviewed(edited) } },
                       discard: { model.manager.review = nil })
                .padding(.bottom, Spacing.extraSmall)
        } else {
            writing
        }
    }

    private var writing: some View {
        VStack(spacing: Spacing.extraSmall) {
            if desk.draft.isEmpty && !desk.working { ManagerStarters { send($0) } }
            HStack(spacing: Spacing.extraSmall) {
                field
                if desk.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !desk.entries.isEmpty {
                        Button("Start over", systemImage: "arrow.counterclockwise") {
                            clearing = true
                        }
                        .accessibilityIdentifier("manager-clear")
                    }
                } else {
                    Button("Send", systemImage: "arrow.up") { send() }
                        .accessibilityIdentifier("manager-send")
                }
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.textTertiary)
            mark
        }
        .padding(.bottom, Spacing.extraSmall)
        .confirmationDialog("Start over?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Start over", role: .destructive) { Task { await model.clearManager() } }
        } message: {
            Text("The manager forgets this conversation and everything in it.")
        }
    }

    private var field: some View {
        TextField("Ask the manager", text: $model.manager.draft, axis: .vertical)
            .font(Typography.prose)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1...4)
            .focused($typing)
            .submitLabel(.send)
            .onSubmit { send() }
            .padding(.horizontal, Spacing.extraSmall)
            .padding(.vertical, Spacing.xxs + 2)
            .background(
                // Tighter than the cards above it, never wider: a control inside a page of
                // Radius.medium cards is the smaller corner, which is the rule this app fixed
                // once already on the review card's buttons.
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Palette.textPrimary.opacity(0.06))
            )
            // Also what a UI test asks for to know the panel is open. An identifier on the
            // panel's own container looked tidier and was wrong: SwiftUI pushes a container's
            // identifier down onto every descendant, so the field, both buttons and the mark
            // all came back called `manager-panel` and nothing could be addressed at all.
            .accessibilityIdentifier("manager-field")
    }

    /// Hold to talk, exactly as everywhere else. `isMine` is true because this recorder is this
    /// panel's own and nothing else on the screen reads it.
    private var mark: some View {
        TalkControl(
            recorder: recorder,
            mode: model.preferences.talkMode,
            isMine: true,
            onStart: { typing = false },
            onClip: {
                desk.tab = .manager
                await model.askManager(clip: $0)
            },
            content: { state in
                TalkMark(state: state, level: recorder.level, saying: "Talk to the manager",
                         // Held for reading under the same switch as a session's clip: a
                         // mishearing here is an instruction to every session, not one.
                         confirms: model.preferences.confirms)
                    // Its own name: the panel sits beside every session page, and a second
                    // `talk-mark` is what a test asking for the session's own mark finds first.
                    .accessibilityIdentifier("manager-talk-mark")
            }
        )
    }

    private func send() { send(desk.draft) }

    private func send(_ words: String) {
        desk.tab = .manager
        Task { await model.askManager(words) }
    }

    /// The last thing drawn, whichever kind it is: the working line, the sentence being written,
    /// or the newest entry.
    private func bottom(_ scroller: ScrollViewProxy) {
        let last: AnyHashable? = desk.working ? "working" : !desk.partial.isEmpty ? "partial"
            : desk.entries.last.map { AnyHashable($0.id) }
        guard let last else { return }
        withAnimation(Motion.arriving) { scroller.scrollTo(last, anchor: .bottom) }
    }

    /// One second while a run is in flight, four while it is not. The Mac answers this off a
    /// file whatever the manager is doing, so a fast poll costs a request rather than a model.
    /// The tray rides the same loop: one panel, one pace.
    private func poll() async {
        guard desk.open else { return }
        while !Task.isCancelled && desk.open {
            await model.pollManager()
            // What was already said before this launch is not unread. After the poll that
            // brought it, never before: on a cold start the conversation is empty until then.
            if desk.readEntry == 0 { desk.readEntry = desk.entries.last?.id ?? 0 }
            await model.pollTray()
            try? await Task.sleep(for: .seconds(desk.working ? 1 : 4))
        }
    }
}
