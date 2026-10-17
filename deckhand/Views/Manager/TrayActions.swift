import DeckhandKit
import Foundation

/// The two halves of the manager panel.
enum ManagerTab {
    case tray, manager
}

/// The tray's half of the model: one poll, one answer, one way to a session.
@MainActor
extension AppModel {
    /// Everything open on every machine, and every update after the cursor. Cheap: the Mac reads
    /// a few slip pages off disk and answers, so it rides the manager's own poll.
    func pollTray() async {
        guard let client = settings.client() else { return }
        do {
            manager.tray.absorb(try await client.tray(since: manager.tray.cursor))
        } catch {
            manager.trayNote = reason(error)
        }
    }

    /// Answer a slip without its page. Returns why it did not go, for the slip's own row, or nil.
    ///
    /// The same route the page's own buttons use, as the person, because it is the person. An
    /// answer the Mac wrote down but could not deliver is still an answer — the file is the
    /// record — so the slip leaves and the note says the session was not told.
    func answerSlip(_ slip: TraySlip, of row: TraySession, valueJSON: String) async -> String? {
        guard let client = settings.client() else { return "No Mac is paired." }
        do {
            let sent = try await client.answer(slip.id, in: row.session, valueJSON: valueJSON,
                                               route: preferences.route)
            manager.tray.drop(slip: slip.id, of: row.session)
            if !sent.went {
                manager.trayNote = "\(row.name) has the answer on disk but was not told: "
                    + (sent.stoppedBy.map { "\($0) stopped it" } ?? sent.deliveryError ?? "no route")
            }
            await pollTray()
            return nil
        } catch {
            return reason(error)
        }
    }

    /// Leave the panel for one session's page.
    func goTo(session id: String) async {
        manager.open = false
        await open(.session(id))
    }
}
