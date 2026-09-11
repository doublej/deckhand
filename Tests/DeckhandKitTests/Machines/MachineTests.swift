import Foundation
import Testing

@testable import DeckhandKit

private func machine(_ id: String, label: String, primary: Bool = false) -> Machine {
    Machine(id: id, label: label, system: "linux", reachable: true, error: "", primary: primary)
}

private func session(_ name: String, on machine: String?, cwd: String = "/x") -> Session {
    Session(
        sessionId: "id-\(machine ?? "none")-\(name)",
        pid: 1,
        name: name,
        cwd: cwd,
        folder: "x",
        status: "idle",
        updatedAt: 0,
        tty: "ttys001",
        pane: nil,
        machine: machine
    )
}

@Suite("What a machine may be called, and what a blank or endless label does to a row")
struct MachineTitleTests {
    @Test("a label is shown as it was written")
    func plain() {
        #expect(machine("ubuntu", label: "Ubuntu").title == "Ubuntu")
    }

    @Test("a blank label falls back to the id, which is always there and always short")
    func blank() {
        #expect(machine("ubuntu", label: "").title == "ubuntu")
        #expect(machine("ubuntu", label: "   ").title == "ubuntu")
    }

    @Test("a long label is cut rather than allowed to push the state word off the row")
    func long() {
        let title = machine("m2", label: String(repeating: "x", count: 80)).title
        #expect(title.count == Machine.titleLimit)
        #expect(title.hasSuffix("…"))
    }

    @Test("unreachable is off when nothing was said, and an error when something was")
    func states() {
        let asleep = Machine(id: "u", label: "U", system: "linux", reachable: false, error: "")
        let broken = Machine(id: "u", label: "U", system: "linux", reachable: false, error: "boom")
        #expect(asleep.state == .off)
        #expect(broken.state == .err)
        #expect(machine("u", label: "U").state == .online)
    }
}

@Suite("A star follows the session on its own machine")
struct PreferenceKeyTests {
    @Test("the same name on two machines is two different sessions")
    func namesDoNotCollide() {
        var prefs = Preferences()
        prefs.toggleFavorite(session("deckhand", on: "m2"))

        #expect(prefs.isFavorite(session("deckhand", on: "m2")))
        #expect(!prefs.isFavorite(session("deckhand", on: "ubuntu")))
    }

    @Test("a session from a Mac that names no machine keys under the bare name")
    func noMachine() {
        #expect(Preferences.key(session("deckhand", on: nil)) == "deckhand")
        #expect(Preferences.key(session("deckhand", on: "")) == "deckhand")
    }

    @Test("stars written before the network are filed under the machine they were always about")
    func migration() {
        var prefs = Preferences(favorites: ["deckhand"], hidden: ["noisy"])
        prefs = prefs.migrated(onto: "m2")

        #expect(prefs.favorites == ["m2/deckhand"])
        #expect(prefs.hidden == ["m2/noisy"])
        #expect(prefs.isFavorite(session("deckhand", on: "m2")))
    }

    @Test("migrating twice changes nothing, so it is safe to run on every listing")
    func migrationIsIdempotent() {
        let once = Preferences(favorites: ["deckhand"]).migrated(onto: "m2")
        #expect(once.migrated(onto: "m2") == once)
    }

    @Test("a rename moves the star on that session's machine and leaves the other one alone")
    func renaming() {
        var prefs = Preferences(favorites: ["m2/deckhand", "ubuntu/deckhand"])
        prefs.renamed(from: "deckhand", to: "deckhand-2", on: "m2")

        #expect(prefs.favorites == ["m2/deckhand-2", "ubuntu/deckhand"])
    }

    @Test("a key shows only the name half on a screen that lists keys")
    func naming() {
        #expect(Preferences.name(of: "m2/deckhand") == "deckhand")
        #expect(Preferences.name(of: "deckhand") == "deckhand")
    }
}

@Suite("Two machines with the same path are two projects")
struct ProjectGroupMachineTests {
    @Test("one path on two machines does not merge into one block")
    func doesNotMerge() {
        let groups = ProjectGroup.of(
            [
                session("a", on: "m2", cwd: "/Users/jurrejan/dev/x"),
                session("b", on: "mbp15", cwd: "/Users/jurrejan/dev/x")
            ],
            isFavorite: { _ in false }
        )
        #expect(groups.count == 2)
        #expect(Set(groups.map(\.machine)) == ["m2", "mbp15"])
        // Both render the same shortened path, which is exactly why the machine is in the key.
        #expect(Set(groups.map(\.parent)) == ["~/dev"])
    }

    @Test("two sessions on one machine in one folder are still one block")
    func stillGroups() {
        let groups = ProjectGroup.of(
            [
                session("a", on: "m2", cwd: "/Users/jurrejan/dev/x"),
                session("b", on: "m2", cwd: "/Users/jurrejan/dev/x")
            ],
            isFavorite: { _ in false }
        )
        #expect(groups.count == 1)
        #expect(groups[0].sessions.count == 2)
    }
}
