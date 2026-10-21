import DeckhandKit
import Foundation

/// The model's half of a decision: the slip's own bar and the tray both answer through here, and
/// both sign with the phone's key (`PhoneKey`). A decision never takes the route the person chose
/// for speaking — the Mac always types a verified answer as the person, so there is none to pass.
@MainActor
extension AppModel {
    /// One decision, answered from its page's bar. Throws rather than reporting into `status`,
    /// for `answer(_:in:valueJSON:)`'s reason: the viewer covers the status line.
    func answerDecision(_ artifact: Artifact, in session: String, valueJSON: String) async throws
        -> Delivery {
        guard let client = settings.client() else { throw DeckhandError.unauthorized }
        // A decision row always carries its hash; one without it is a Mac this build cannot read.
        guard let hash = artifact.hash else { throw DeckhandError.badResponse }
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(valueJSON.utf8))
        return try await PhoneKey.answer(with: client, artifact: artifact.id, in: session,
                                         hash: hash, value: value)
    }

    /// The tray's twin of `answerSlip`, with the same bookkeeping: why it did not go, or nil.
    func answerTrayDecision(_ slip: TraySlip, of row: TraySession, valueJSON: String) async
        -> String? {
        do {
            let sent = try await answerDecision(slip.artifact, in: row.session, valueJSON: valueJSON)
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

    /// Hand the Mac this phone's key right after pairing by code. Why it failed, or nil.
    func registerDecisionKey() async -> String? {
        guard let client = settings.client() else { return nil }
        do {
            try await PhoneKey.register(with: client)
            return nil
        } catch {
            return reason(error)
        }
    }
}
