import DeckhandKit
import SwiftUI

/// The top of a session page: who it is, what it is doing, how much window it has left, and
/// everything you can do *to* it as opposed to say to it.
///
/// Split out of `SessionView` when that file passed 280 lines. The seam is a real one rather
/// than a line count: below this strip the page is three interchangeable panes swiped between,
/// and none of them know anything about ending a session or clearing it.
///
/// What it does not own is the presenting, with one exception it does own. The sheets this *menu*
/// opens are declared on the page, because they belong to the whole page and not to the strip that
/// triggered it — so they arrive here as bindings and this view only ever sets them. What used to
/// be seven more of them is the dashboard's now, presented from the square that opens it. Renaming
/// is the exception and follows that same rule from the other end: it is triggered by the title in
/// this strip and by nothing else, so the state and the sheet are both here.
struct SessionHead: View {
    @Bindable var model: AppModel
    let session: Session
    @Binding var confirming: Confirmation?
    @Binding var reading: Bool
    /// How many panes there are and which one is showing. The page indicator lives here rather
    /// than at the foot because the row it sits on was already being drawn — so the bar of words
    /// that used to be down there cost a band of the screen, and this costs nothing.
    let pages: Int
    let lit: Int
    /// Whether the Mac is writing this session's briefing. It was in the tab bar, which is gone;
    /// it belongs beside the other things this strip says about the session's state.
    let working: Bool
    /// The page's recorder, so a new name can be said rather than typed. Handed down for the
    /// reason every sheet here is lent it: one recorder per screen, or a sheet that made its own
    /// would record while the page behind it stayed teal.
    let say: Dictation
    /// Whether the rename sheet is up. This view's own, unlike the two bindings above: it belongs
    /// to the title that opens it, the way a dashboard square owns the sheet it presents.
    @State private var renaming = false
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
        .background { ProjectBanner(model: model, session: session) }
        .sheet(isPresented: $renaming) {
            Renaming(session: session, say: say) { wanted in
                Task { await model.rename(session, to: wanted) }
            }
        }
    }

    /// The name and the way to everything else. Nothing more.
    ///
    /// The chevron went with the tab bar: the panes are swiped between now and a swipe from the
    /// left edge of the first leaves the session, so the arrow was a second way to do a thing the
    /// page already does, taking a corner of every screen to offer it. The way out is still named
    /// in the menu — a gesture nobody is told about is not a way out for somebody using VoiceOver.
    ///
    /// The tile went too. A session's glyph tells one row from another in a list of them; on the
    /// session's own page there is only one session, and it was 28 points of picture saying what
    /// the name beside it already said.
    ///
    /// **The name is the thing you rename now.** It was a square on the dashboard printing the
    /// same name this header already draws in this same 20pt — two copies of one word, and the
    /// one you could press was the lower. The title took the job and the square is gone.
    private var header: some View {
        HStack(spacing: Spacing.extraSmall) {
            name
            Spacer(minLength: Spacing.extraSmall)
            controls
        }
        .padding(.leading, Spacing.medium)
        .padding(.trailing, Spacing.small)
        .padding(.top, Spacing.xxs)
    }

    /// The session's name, and — where a rename could actually land — the way to change it.
    ///
    /// The pencil is here rather than nowhere because this app labels nothing at rest, and a
    /// title that is secretly tappable is a rename nobody finds. **It is the menu's own size,
    /// weight and colour**, which is measured rather than tidy: a bare `pencil` in tertiary ink
    /// at 11pt photographs as a stray slash after the name, near enough to a typo that the thing
    /// it advertises disappears. Circled, accent, 16pt semibold is what this strip already uses
    /// to mean "press this".
    ///
    /// **Absent, never dimmed, when it cannot work** (`Session.renames`): a Codex thread and a
    /// session tmux cannot see get the title alone, and OpenCode renames over its own API. The
    /// square it replaces said "Needs its pane"; a strip has nowhere to put that, and a dead pencil
    /// with no explanation is worse than a title that simply is one.
    @ViewBuilder private var name: some View {
        if !session.renames {
            title
        } else {
            Button { renaming = true } label: {
                HStack(spacing: Spacing.xxs) {
                    title
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rename \(session.name)")
            .accessibilityIdentifier("session-rename")
        }
    }

    private var title: some View {
        Text(session.name)
            .font(Typography.pageTitle)
            .foregroundStyle(Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// What is left of the menu once the dashboard exists: the way out, the file itself, and the
    /// two things nothing brings back.
    ///
    /// It used to hold eleven items, and seven of them are squares now — with a number on each,
    /// which is the whole reason the grid is better than this was. Four stayed, each for its own
    /// reason. **Sessions** is here because leaving is a swipe from the leading edge and a gesture
    /// nobody is told about is not a way out for somebody using VoiceOver. **Raw transcript** is
    /// here because there is no honest number to put on a square for it — a tile that is a word
    /// in a box is a menu row drawn four times too large. And **clear** and **exit** are here
    /// because a mis-tap on either cannot be undone, and a grid of identical squares is exactly
    /// where a thumb moves fastest.
    private var controls: some View {
        Menu {
            here
            inside
            // Last and on their own, because this is the only group in the menu where a
            // mis-tap costs something. `isIrreversible` and not `asksFirst`, which used to be
            // the same set and is not any more: compacting asks first too, and it belongs on
            // the dashboard where the window figure that decides it is printed — not in here,
            // drawn red among the two nothing brings back.
            // Claude Code's alone: both are its own command typed into a pane, and neither Codex
            // nor OpenCode has one or an equivalent.
            if session.endsByKeys {
                Section("Run") {
                    ForEach(Control.allCases.filter(\.isIrreversible), id: \.self) { action in
                        Button(action.label, systemImage: action.symbol, role: .destructive) {
                            ask(action)
                        }
                        .disabled(hasNoPane)
                    }
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
    ///
    /// "Show on the Mac" left: it is a square now, and the square says which pane it will bring
    /// forward, which this row never could.
    private var here: some View {
        Section {
            Button("Sessions", systemImage: "chevron.left") { dismiss() }
        }
    }

    /// The file the whole app is a reading of.
    ///
    /// Always reachable, not only when something looks wrong — and it stayed in the menu rather
    /// than becoming a square because nothing true and short can be printed on one for it. The
    /// line count is not known until it has been fetched, and a tile whose number arrives only
    /// after you press it is a tile with no number.
    private var inside: some View {
        Section("Look inside") {
            Button("Raw transcript", systemImage: "scroll") { reading = true }
        }
    }

    /// The control's own question, or — for one that asks nothing — just send it. Only controls
    /// that ask reach this menu, so the second branch is unreachable today and written anyway: a
    /// menu item that silently does nothing is the worst way for a filter to turn out wrong.
    private func ask(_ action: Control) {
        if let asked = Confirmation(action, of: session, on: model) {
            confirming = asked
        } else {
            Task { await model.control(action, of: session) }
        }
    }

    /// Whether the two keystrokes left in this menu can work at all.
    ///
    /// It used to switch off the *whole* menu, which was right while every item in it was a
    /// keystroke and wrong the moment one was not — with iTerm unreachable the menu was the only
    /// way to the raw transcript, and the menu was the thing switched off. It is on the two
    /// buttons now, where it has always belonged.
    private var hasNoPane: Bool { session.pane == nil }

    /// One slim row under the header carrying everything that is true of the session rather than
    /// something you press: how much window it has left, whether the Mac is writing about it, and
    /// which of the panes you are on.
    ///
    /// The meter is the one number that changes what you would do next — compact it now, or carry
    /// on — so it is on every pane. The dots are here because this row exists anyway: the panes
    /// are swiped between now, and a bar of their names at the foot of the screen was a band of
    /// chrome to say something a dot each says in the space already spare on this line.
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
            if let word = session.providerWord { ProviderWord(word) }
            StateWord(session.runState)
            dots
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.small)
    }

    /// Where you are among the panes, and how many there are. Not a control: the panes are swiped
    /// between, and dots you can hit are dots somebody will try to hit.
    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<pages, id: \.self) { index in
                Circle()
                    .fill(index == lit ? accent : Palette.textTertiary.opacity(0.35))
                    .frame(width: 5, height: 5)
            }
        }
        .animation(Motion.opening, value: lit)
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
