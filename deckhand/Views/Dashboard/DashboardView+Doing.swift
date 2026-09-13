import DeckhandKit
import SwiftUI

/// The squares that change something rather than open something.
///
/// Three of the four are a keystroke in an iTerm pane, so those three are dimmed and say why when
/// the Mac cannot see one — the same rule `SessionHead.hasNoPane` applies to what is left of the
/// menu. Clearing the inbox is the exception and deliberately gated on something else: it is a
/// file the daemon writes rather than anything typed, so it stays live with iTerm unreachable and
/// goes dim only when there is nothing queued to draw a line under.
///
/// **Two of the four controls are not here and are not going to be.** `clear` and `exit` cannot be
/// undone — they are the set `Control.asksFirst` names — and a grid is eleven identical squares a
/// thumb moves across quickly. They stayed in the `…` menu, in their own section, drawn red and
/// asking first, which is the arrangement that was already protecting them. The two that *are*
/// here are the two that only ever make a session do less: Escape takes work away, and compacting
/// folds a conversation rather than losing it. It is the same line the Lock Screen card draws,
/// for the same reason.
extension DashboardView {
    /// The name, which is also the way to change it. `/rename` is typed into the pane, so this
    /// needs one — see `SessionHead.hasNoPane`, which is the same rule one file over.
    var nameTile: some View {
        DashboardTile(glyph: "text.cursor",
                      title: "Name",
                      value: session.name,
                      caption: needsPane,
                      ready: hasPane,
                      spoken: "Rename this session") { opened = .name }
    }

    /// Where it is running, and bringing that window to the front. The pane's own title, because
    /// "which of the nine splits is this" is the question somebody at the Mac is actually asking.
    var macTile: some View {
        DashboardTile(glyph: "display",
                      title: "On the Mac",
                      value: session.pane?.title ?? "No pane",
                      caption: needsPane,
                      ready: hasPane,
                      spoken: "Show this session on the Mac") {
            Task { await model.focus(session) }
        }
    }

    /// What has been said to this session that it has not picked up yet, and the line under it.
    ///
    /// The count is read off the session's own transcript rather than guessed at from the shape
    /// of the conversation, so the square is the inbox rather than a report about it. Clearing is
    /// for prompts that outlived the session that was going to read them, which is why the verb
    /// is the title and the number is underneath: what you read first is what pressing it does.
    var inboxTile: some View {
        let queued = model.queued[session.sessionId] ?? []
        return DashboardTile(glyph: "tray.and.arrow.up",
                             title: "Clear inbox",
                             value: Dashboard.inbox(queued.count),
                             lit: queued.isEmpty ? nil : accent,
                             ready: !queued.isEmpty,
                             spoken: "Clear queued prompts") {
            Task { await model.clearQueue(for: session) }
        }
    }

    /// Escape. The one control worth reaching for while something is running, which is why the
    /// square says whether anything is.
    var stopTile: some View {
        DashboardTile(glyph: Control.cancel.symbol,
                      title: "Stop",
                      value: session.isBusy ? "Busy" : "Idle",
                      caption: needsPane,
                      lit: session.isBusy ? accent : nil,
                      ready: hasPane,
                      spoken: Control.cancel.label) { run(.cancel) }
    }

    /// Whether a keystroke can reach this session at all.
    var hasPane: Bool { session.pane != nil }

    /// The caption a dimmed square carries. Nil while there is a pane, so a working tile is not
    /// carrying a line about a state it is not in — an explanation that is always on screen is
    /// the noise the "nothing is labelled at rest" rule exists to stop.
    var needsPane: String? { hasPane ? nil : "Needs its pane" }

    /// Neither of the two tiles here asks first, by definition: the ones that do are the ones
    /// that are not on this grid. So this is the model directly, exactly as the menu's own
    /// `send` is, and there is no confirmation to route through the page.
    func run(_ action: Control) {
        Task { await model.control(action, of: session) }
    }
}
