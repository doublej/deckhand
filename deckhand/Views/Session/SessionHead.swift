import DeckhandKit
import SwiftUI

/// The top of a session page: who it is, what it is doing, how much window it has left, and
/// everything you can do *to* it as opposed to say to it.
///
/// Split out of `SessionView` when that file passed 280 lines. The seam is a real one rather
/// than a line count: below this strip the page is four interchangeable panes and a tab bar,
/// and none of them know anything about renaming a session or compacting it.
///
/// What it does not own is the presenting. Every sheet and alert this menu opens is declared on
/// the page, because one belongs to the whole page and not to the strip that triggered it — so
/// they arrive here as bindings and this view only ever sets them.
struct SessionHead: View {
    @Bindable var model: AppModel
    let session: Session
    @Binding var confirming: Control?
    @Binding var renaming: Bool
    @Binding var reading: Bool
    @Binding var filtering: Bool
    @Binding var configuring: Bool
    /// How many panes there are and which one is showing. The page indicator lives here rather
    /// than at the foot because the row it sits on was already being drawn — so the bar of four
    /// words that used to be down there cost a band of the screen, and this costs nothing.
    let pages: Int
    let lit: Int
    /// Whether the Mac is writing this session's briefing. It was in the tab bar, which is gone;
    /// it belongs beside the other things this strip says about the session's state.
    let working: Bool
    /// The page's colour, which goes utt orange while the mark at the foot of it is open. Read
    /// from the environment here: `SessionView` is the view that puts it there, and a view never
    /// sees what it hands its own children.
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            fullness
        }
    }

    /// The name and the way to everything else. Nothing more.
    ///
    /// The chevron went with the tab bar: the panes are swiped between now, and a swipe from the
    /// left edge of the first one leaves the session — so the arrow was a second way to do a
    /// thing the page already does, taking a corner of every screen to offer it. The way out is
    /// still named in the menu, because a gesture nobody is told about is not a way out for
    /// somebody using VoiceOver.
    ///
    /// The tile went too. A session's glyph tells one row from another in a list of them; on the
    /// session's own page there is only one session, and it was 28 points of picture saying what
    /// the name beside it already said.
    private var header: some View {
        HStack(spacing: Spacing.extraSmall) {
            Text(session.name)
                .font(Typography.pageTitle)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: Spacing.extraSmall)
            controls
        }
        .padding(.leading, Spacing.medium)
        .padding(.trailing, Spacing.small)
        .padding(.top, Spacing.xxs)
    }

    /// Everything you can do to the session rather than say to it, behind one glyph: bringing
    /// its pane forward, stopping a run, compacting, clearing. A row of four buttons up here
    /// would be more chrome than the header has, and three of the four are rare.
    ///
    /// All of them are keystrokes in its pane, so all of them need one — without a pane the
    /// menu is there and says why rather than quietly doing nothing.
    private var controls: some View {
        Menu {
            here
            setup
            inside
            // Last and on their own, because this is the only group in the menu where a
            // mis-tap costs something. Two of the four cannot be undone at all.
            Section("Run") {
                ForEach(Control.allCases, id: \.self) { action in
                    Button(action.label, systemImage: action.symbol, role: role(action)) {
                        if action.asksFirst { confirming = action } else { send(action) }
                    }
                    .disabled(hasNoPane)
                }
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

    /// Where you go from here. The way back is a menu item because the chevron is gone and a
    /// left-edge swipe, which is what replaced it, is not something VoiceOver offers.
    private var here: some View {
        Section {
            Button("Sessions", systemImage: "chevron.left") { dismiss() }
            Button("Show on the Mac", systemImage: "display") {
                Task { await model.focus(session) }
            }
            .disabled(hasNoPane)
        }
    }

    /// The three things you configure rather than do. All of them open a page, all of them are
    /// rare, and none of them changes the session you are looking at right now — which is why
    /// they are together and why they are not first.
    private var setup: some View {
        Section("Set up") {
            // The sheet seeds itself from the name this session has now, so there is no draft
            // for the page to hold on its behalf.
            Button("Rename…", systemImage: "text.cursor") { renaming = true }
                .disabled(hasNoPane)
            // What the Mac does to words on their way into this session — this session's own
            // setting rather than the Mac's, because what you want done to words going into one
            // project is not what you want done to words going into another.
            Button("Words on the way in…", systemImage: "line.3.horizontal.decrease") {
                filtering = true
            }
            // The folder's own page, reached from the session running in it rather than only
            // from the project picker: this is where a person already is when they want to
            // change what the Mac may do about this work. Keyed by the path, which outlives
            // every session in it — a setting filed under a session id would be gone by morning.
            Button("Project settings…", systemImage: "slider.horizontal.3") { configuring = true }
        }
    }

    /// Looking at what the app is reading, and clearing what it cannot read for you.
    private var inside: some View {
        Section("Look inside") {
            // Always reachable, not only when something looks wrong: every other view here is
            // a reading of that file, and this is the file.
            Button("Raw transcript", systemImage: "scroll") { reading = true }
            // For prompts that outlived the session that was going to read them: a session
            // killed mid-queue leaves its enqueues with nothing to remove them.
            Button("Clear queued prompts", systemImage: "tray.and.arrow.up") {
                Task { await model.clearQueue(for: session) }
            }
            .disabled((model.queued[session.sessionId] ?? []).isEmpty)
        }
    }

    /// Whether the things in that menu which are keystrokes can work at all.
    ///
    /// It used to switch off the whole menu, which was right while every item in it was a
    /// keystroke. Two of them never were — reading the transcript is a file on disk, clearing the
    /// queue is a file the daemon writes — and the filter chain is a third. With iTerm unreachable
    /// the menu was the only way to any of those, and the menu was the thing switched off.
    private var hasNoPane: Bool { session.pane == nil }

    /// Red for the ones that cannot be undone, which is the same set that asks first.
    private func role(_ action: Control) -> ButtonRole? {
        action.asksFirst ? .destructive : nil
    }

    private func send(_ action: Control) {
        Task { await model.control(action, of: session) }
    }

    /// One slim row under the header carrying everything that is true of the session rather than
    /// something you press: how much window it has left, whether the Mac is writing about it, and
    /// which of the panes you are on.
    ///
    /// The meter is the one number that changes what you would do next — compact it now, or carry
    /// on — so it is on every pane. The dots are here because this row exists anyway: the four
    /// panes are swiped between now, and a bar of four words at the foot of the screen was a band
    /// of chrome to say something four dots say in the space already spare on this line.
    private var fullness: some View {
        HStack(spacing: Spacing.extraSmall) {
            if let context = session.context {
                Dial(context.share, tint: Palette.pressure(context.pressure))
                Text(context.line)
                    .font(Typography.hint)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            // Only when it is idle. "How long since it last said anything" is the question you
            // ask about a session that has stopped; a session mid-turn last spoke now, and the
            // registry's own stamp is the age of an idle session and nothing else.
            if !session.isBusy {
                Text(subtitle)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: Spacing.extraSmall)
            if working { ProgressView().controlSize(.mini) }
            StateWord(session.isBusy ? .busy : .idle)
            dots
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.small)
    }

    /// Where you are among the panes, and how many there are. Not a control: the panes are swiped
    /// between, and four dots you can hit are four dots somebody will try to hit.
    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<pages, id: \.self) { index in
                Circle()
                    .fill(index == lit ? accent : Palette.textTertiary.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(.snappy(duration: 0.2), value: lit)
        .accessibilityElement()
        .accessibilityLabel("Pane \(lit + 1) of \(pages)")
    }

    /// Where it is and when it last spoke — minus the half that is already the title above it.
    /// A session started from the picker is named after its own folder, so this read "deckhand"
    /// over "deckhand · 2m ago": two lines of chrome to say one word and a time.
    private var subtitle: String {
        let ago = session.lastActive.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        let sameWord = session.folder.caseInsensitiveCompare(session.name) == .orderedSame
        return sameWord ? ago : "\(session.folder) · \(ago)"
    }
}

/// How full the window is, as a ring rather than a bar.
///
/// The bar ran the width of the page to say one number, which is a lot of screen for something
/// you glance at — and a bar reads as a thing filling up over time, which is right, but it read
/// as the *page's* progress rather than the session's. A ring is the same fact in thirteen
/// points, beside the number it is about.
///
/// It never draws completely empty: a session with a barely-touched window would otherwise show
/// a plain grey circle, which reads as "no data" rather than "hardly any".
private struct Dial: View {
    private let share: Double
    private let tint: Color
    private let size: CGFloat = 13
    private let thickness: CGFloat = 2.5

    init(_ share: Double, tint: Color) {
        self.share = min(max(share, 0.03), 1)
        self.tint = tint
    }

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: thickness)
            Circle()
                .trim(from: 0, to: share)
                .stroke(tint, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                // From the top, the way a clock face is read, rather than from three o'clock.
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
