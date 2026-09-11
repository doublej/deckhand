import DeckhandKit
import Foundation

/// The machines the Mac can reach, and what the rail does with them.
///
/// Its own file for the reason every other `extension AppModel` has one: `Model.swift` holds
/// only what has to be stored on the class itself.
///
/// **The phone never learns a hand exists.** A machine is a name on a row and a way to slice the
/// list; how the Mac reaches one is the Mac's, and nothing here has an address in it.
extension AppModel {
    /// Take a listing's machines, and — once, on the first listing that names the primary —
    /// carry the favourites and hidden rows written before any of this onto it.
    ///
    /// The migration runs here rather than at launch because this is the first moment the phone
    /// can know which machine those names were always about. It is idempotent: a key that
    /// already names a machine is left alone, so running it on every listing costs a set walk.
    func absorb(_ found: [Machine]) {
        machines = found
        if let primary = found.first(where: \.isPrimary) {
            let moved = preferences.migrated(onto: primary.id)
            if moved != preferences {
                preferences = moved
                preferences.save()
                logger.info("filed favourites and hidden rows under \(primary.id)")
            }
        }
        // A filter pointing at a machine the Mac no longer lists would hide the whole rail with
        // no row left to switch it off from.
        if let only = onlyMachine, !found.contains(where: { $0.id == only }) {
            onlyMachine = nil
        }
    }

    /// Whether the rail is showing that machine. Everything, until one is picked.
    func shows(_ machine: String?) -> Bool {
        onlyMachine == nil || onlyMachine == (machine ?? "")
    }

    /// Whether a machine is worth naming on screen at all. One machine needs no label, which is
    /// what keeps a rail that has always been one Mac looking exactly as it did.
    var namesMachines: Bool { machines.count > 1 }

    /// What a machine is called, for a screen holding only its id. Falls back to the id, which
    /// is what a machine the listing has not caught up with still has.
    func label(of machine: String?) -> String {
        guard let machine, !machine.isEmpty else { return "" }
        return machines.first { $0.id == machine }?.title ?? machine
    }

    /// How many sessions on the rail are that machine's. Counted off the listing rather than
    /// asked for: the Mac already said, and a second number could disagree with the first.
    func sessionCount(on machine: Machine) -> Int {
        sessions.filter { ($0.machine ?? "") == machine.id }.count
    }

    /// Show one machine's sessions, or all of them again when the same row is tapped twice.
    func show(only machine: Machine?) {
        onlyMachine = (onlyMachine == machine?.id) ? nil : machine?.id
    }
}
