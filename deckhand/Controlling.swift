import DeckhandKit
import Foundation

/// A question the page is about to put up, and the thing to do if the answer is yes.
///
/// The page holds one of these at a time and draws one dialog from it, so every surface that can
/// set it — the session menu, a dashboard square — gets the same sheet and cannot grow one of its
/// own. It carries the `Caution` rather than a `Control`, which is the whole widening: clearing
/// an inbox needs confirming and is not a keystroke in a pane, so a slot typed as `Control` could
/// not hold it and the alternative was a second `confirmationDialog` on the same page.
///
/// The words are still the action's own. Nothing here writes a sentence: a control hands over
/// `Control.caution(about:)` and the inbox hands over `Caution.clearingInbox(of:)`.
@MainActor
struct Confirmation {
    let caution: Caution
    /// What happens on yes. Not `go`: SwiftLint wants three characters and this repo has
    /// already renamed two-letter names three times — see `.claude/rules/swift-naming.md`.
    let proceed: () async -> Void

    init(caution: Caution, proceed: @escaping () async -> Void) {
        self.caution = caution
        self.proceed = proceed
    }

    /// A control as the question it asks, or nil for one that asks nothing.
    ///
    /// Failable rather than "always a question" because `cancel` is a real control with no
    /// caution, and stopping a run is the one thing a thumb may fire straight off the grid.
    init?(_ action: Control, of session: Session, on model: AppModel) {
        guard let caution = action.caution(about: session.name) else { return nil }
        self.init(caution: caution) { await model.control(action, of: session) }
    }
}

/// The four things you do *to* a session rather than say to it.
///
/// Split from `Model.swift` for size, but they belong together anyway: three of them are
/// keystrokes typed into that session's own pane on the Mac, so none of them work on a session
/// with no pane, and all of them are answered by the transcript catching up rather than by a
/// reply. Nothing here waits to be told it worked.
@MainActor
extension AppModel {
    /// Stop, compact or clear. Nothing to fetch afterwards: the transcript poll picks up
    /// whatever the session does about it, which is the honest picture either way.
    func control(_ action: Control, of session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            try await client.control(action, of: session.sessionId)
            self.status = "\(action.label) — sent to \(session.name)"
            if action == .clear { self.turns = [] }
        }
    }

    /// Rename a session on the Mac, and move what you had decided about it onto the new name.
    ///
    /// The listing catches up on its own once the session actually runs the command — which
    /// for a busy one is when its turn ends, so the status line says it has been asked rather
    /// than claiming it is done.
    func rename(_ session: Session, to name: String) async {
        guard let client = settings.client() else { return }
        let wanted = name.collapsed
        guard !wanted.isEmpty, wanted != session.name else { return }
        await run {
            // The Mac carries the filter chain, because the chain is filed under the name and the
            // phone never holds one. Both halves move on the same optimism: a busy session runs
            // the command when its turn ends, and the star moves now either way.
            let carried = try await client.rename(session.sessionId, to: wanted)
            self.preferences.renamed(from: session.name, to: wanted, on: session.machine)
            self.preferences.save()
            let when = session.isBusy
                ? "\(session.name) will be \(wanted) when it finishes this turn"
                : "\(session.name) is now \(wanted)"
            self.status = carried ? "\(when) · filters moved with it" : when
        }
    }

    /// Throw away whatever the session's inbox still claims to hold.
    ///
    /// For prompts that outlived the session that was going to read them: killed mid-queue, the
    /// enqueues stay in the transcript with nothing to remove them, and the replay cannot tell
    /// that from a message still waiting.
    func clearQueue(for session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            try await client.clearQueue(of: session.sessionId)
            self.queued[session.sessionId] = []
            self.status = "Cleared \(session.name)'s inbox"
        }
    }

    func focus(_ session: Session) async {
        guard let client = settings.client() else { return }
        await run {
            try await client.focus(session.sessionId)
            self.status = "Focused \(session.name) on the Mac"
        }
    }
}
