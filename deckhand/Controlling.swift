import DeckhandKit
import Foundation

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
            try await client.rename(session.sessionId, to: wanted)
            self.preferences.renamed(from: session.name, to: wanted)
            self.preferences.save()
            self.status = session.isBusy
                ? "\(session.name) will be \(wanted) when it finishes this turn"
                : "\(session.name) is now \(wanted)"
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
