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
    @Binding var wantedName: String
    @Binding var reading: Bool
    @Binding var filtering: Bool
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
}
