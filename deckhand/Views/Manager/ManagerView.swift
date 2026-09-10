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
/// the Mac. The conversation is `TurnCard`s — the same card the session transcript uses, for the
/// same reason — and everything the manager *did* is a line rather than a card.
struct ManagerView: View {
    @Bindable var model: AppModel
    @State private var recorder = Recorder()
    @State private var clearing = false
    /// The panel's name, shown as it arrives and then gone. The same move the session panes make
    /// when one is swiped to: a swipe can be accidental and four dots cannot say where you are.
    /// It must never become permanent — a label that stayed would be a title bar.
    @State private var named = false
    @FocusState private var typing: Bool

    private var desk: ManagerDesk { model.manager }
    private var accent: Color { Palette.accent(recording: recorder.isRecording) }

    var body: some View {
        VStack(spacing: 0) {
            conversation
            foot
        }
        .padding(.horizontal, Spacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.lcdGround.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .accent(accent)
        .overlay(alignment: .top) { arrival }
        .accessibilityIdentifier("manager-panel")
        .task(id: desk.open) { await poll() }
        .onChange(of: desk.open) { _, now in
            named = now
            if !now { typing = false }
        }
    }

    /// Everything said, oldest first, with the working line after it when the Mac is still going.
    private var conversation: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    if desk.entries.isEmpty { opening }
                    ForEach(Array(desk.entries.enumerated()), id: \.element.id) { index, entry in
                        ManagerLine(entry: entry, showsRole: shows(index))
                            // On the wrapper rather than on the card: an act draws no card, and
                            // a scroll-to that lands on one would silently do nothing.
                            .id(entry.id)
                    }
                    if desk.working { ActiveLine(doing: nil).padding(.top, Spacing.xxs) }
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
    private var foot: some View {
        VStack(spacing: Spacing.extraSmall) {
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
            .onSubmit(send)
            .padding(.horizontal, Spacing.extraSmall)
            .padding(.vertical, Spacing.xxs + 2)
            .background(
                // Tighter than the cards above it, never wider: a control inside a page of
                // Radius.medium cards is the smaller corner, which is the rule this app fixed
                // once already on the review card's buttons.
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Palette.textPrimary.opacity(0.06))
            )
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
            onClip: { await model.askManager(clip: $0) },
            content: { state in
                TalkMark(state: state, level: recorder.level,
                         // Nothing here is held for reading first: the review card exists
                         // because a prompt into a busy session cannot be undone, and a
                         // sentence to the manager can simply be followed by another.
                         confirms: false)
            }
        )
    }

    /// The name, on arrival and for a second. See `named`.
    private var arrival: some View {
        Text("MANAGER")
            .font(Typography.eyebrow)
            .tracking(2)
            .foregroundStyle(Palette.textTertiary)
            .padding(.top, Spacing.extraSmall)
            .opacity(named ? 1 : 0)
            .animation(Motion.fading, value: named)
            .allowsHitTesting(false)
            .task(id: named) {
                guard named else { return }
                try? await Task.sleep(for: .seconds(1))
                named = false
            }
    }

    private func shows(_ index: Int) -> Bool {
        guard index > 0 else { return true }
        return desk.entries[index - 1].role != desk.entries[index].role
    }

    private func send() {
        let words = desk.draft
        Task { await model.askManager(words) }
    }

    private func bottom(_ scroller: ScrollViewProxy) {
        guard let last = desk.entries.last?.id else { return }
        withAnimation(Motion.arriving) { scroller.scrollTo(last, anchor: .bottom) }
    }

    /// One second while a run is in flight, four while it is not. The Mac answers this off a
    /// file whatever the manager is doing, so a fast poll costs a request rather than a model.
    private func poll() async {
        guard desk.open else { return }
        while !Task.isCancelled && desk.open {
            await model.pollManager()
            try? await Task.sleep(for: .seconds(desk.working ? 1 : 4))
        }
    }
}
