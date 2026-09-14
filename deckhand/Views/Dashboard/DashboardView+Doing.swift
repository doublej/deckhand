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
/// **Two of the squares here ask before they run, and neither brings a dialog with it.** Compact
/// and Clear inbox both hand a `Confirmation` to the page and the page draws the one sheet it has
/// always drawn. Clearing an inbox is the reason that slot is no longer typed as `Control`: it
/// costs something worth a question — prompts waiting are dropped and the session never reads
/// them — and it is not a keystroke, so the only other way to ask would have been a second
/// dialog on this pane.
///
/// **Two of the four controls are not here and are not going to be.** `clear` and `exit` cannot be
/// undone — they are the set `Control.isIrreversible` names — and a grid is ten identical squares
/// a thumb moves across quickly. They stayed in the `…` menu, in their own section, drawn red and
/// asking first, which is the arrangement that was already protecting them. The two that *are*
/// here are the two that only ever make a session do less: Escape takes work away, and compacting
/// folds a conversation rather than losing it. It is the same line the Lock Screen card draws,
/// for the same reason.
///
/// **Compact asks before it runs, and it is still a square.** Those are two different questions
/// and the split is `Control`'s: `asksFirst` is whether the phone puts a question in front of it,
/// `isIrreversible` is whether anything can bring it back. Compacting costs the detail of
/// everything said so far, which is worth a sentence and a second tap; it is not `clear`, and
/// demoting it into the red section would have said it was. So the square stays — it is the one
/// that prints the window figure the decision is made on — and `run` routes it through the page's
/// dialog.
extension DashboardView {
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
                             // The opening line of each, because "is this worth keeping" is the
                             // only question somebody hovering over Clear is actually asking,
                             // and it cannot be answered by a count.
                             preview: Dashboard.few(queued).compactMap {
                                 Dashboard.opening($0.text)
                             },
                             // Behind a prompt, the same as the subagents: a queued prompt is
                             // words waiting to be typed into a session, which is the one thing
                             // in this app that literally is a line at a terminal.
                             look: .terminal,
                             lit: queued.isEmpty ? nil : accent,
                             ready: !queued.isEmpty,
                             spoken: "Clear queued prompts") {
            // Through the page's one dialog, the same as Compact beside it. Clearing an inbox is
            // **not** a `Control` — the daemon writes a timestamp rather than typing anything
            // into a pane — so the slot it lands in is a `Confirmation` and the words are
            // `Caution`'s own. That widening is the whole reason this square can ask at all
            // without a second sheet on the page.
            confirming = Confirmation(caution: .clearingInbox(of: session.name)) {
                await model.clearQueue(for: session)
            }
        }
    }

    /// Escape. The one control worth reaching for while something is running, which is why the
    /// square says whether anything is. A Codex session needs no pane for it: the Mac asks Codex
    /// to interrupt its own turn.
    var stopTile: some View {
        let reachable = hasPane || session.isCodex
        return DashboardTile(glyph: Control.cancel.symbol,
                             title: "Stop",
                             value: session.isBusy ? "Busy" : "Idle",
                             caption: reachable ? nil : needsPane,
                             lit: session.isBusy ? accent : nil,
                             ready: reachable,
                             spoken: Control.cancel.label) { run(.cancel) }
    }

    /// Whether a keystroke can reach this session at all.
    var hasPane: Bool { session.pane != nil }

    /// The caption a dimmed square carries. Nil while there is a pane, so a working tile is not
    /// carrying a line about a state it is not in — an explanation that is always on screen is
    /// the noise the "nothing is labelled at rest" rule exists to stop.
    var needsPane: String? { hasPane ? nil : "Needs its pane" }

    /// A control from a square, through the page's one confirmation where the control asks for
    /// one.
    ///
    /// Compacting asks now, so this is no longer the model directly. It is the *same* dialog the
    /// menu's two use — `SessionView.confirming`, reading its words off the control's own
    /// `Caution` — rather than a second one on this pane: an action carrying its own question is
    /// the whole reason that type exists, and a dialog per surface is how one of them ends up
    /// saying "Clear this?" before compacting.
    func run(_ action: Control) {
        if let asked = Confirmation(action, of: session, on: model) {
            confirming = asked
        } else {
            Task { await model.control(action, of: session) }
        }
    }
}
