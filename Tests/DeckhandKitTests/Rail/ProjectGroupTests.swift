import Foundation
import Testing

@testable import DeckhandKit

private func session(_ name: String, cwd: String, updatedAt: Double = 0) -> Session {
    Session(
        sessionId: "id-\(name)",
        pid: abs(name.hashValue % 90000),
        name: name,
        cwd: cwd,
        folder: cwd.split(separator: "/").last.map(String.init) ?? cwd,
        status: "idle",
        updatedAt: updatedAt,
        tty: "ttys001",
        pane: nil
    )
}

private let deckhand = "/Users/jurrejan/dev/multi-stack/deckhand"
private let quiz = "/Users/jurrejan/dev/web/the-ultimate-music-quiz"

@Suite("Sessions grouped by the project they are working in")
struct ProjectGroupTests {
    @Test("sessions in one checkout become one block")
    func grouping() {
        let groups = ProjectGroup.of(
            [
                session("deckhand", cwd: deckhand, updatedAt: 30),
                session("music-quiz", cwd: quiz, updatedAt: 20),
                session("deckhand-2", cwd: deckhand, updatedAt: 10)
            ],
            isFavorite: { _ in false }
        )
        #expect(groups.count == 2)
        #expect(groups[0].sessions.map(\.name) == ["deckhand", "deckhand-2"])
        #expect(groups[1].sessions.map(\.name) == ["music-quiz"])
    }

    @Test("the folder is the title and the rest of the path sits under it, said once")
    func nameAndParent() {
        let group = ProjectGroup(path: deckhand, sessions: [], hasFavorite: false)
        #expect(group.name == "deckhand")
        #expect(group.parent == "~/dev/multi-stack")
    }

    @Test("a favourite lifts its whole project instead of splitting it")
    func favoritesPromoteTheProject() {
        let groups = ProjectGroup.of(
            [
                session("music-quiz", cwd: quiz, updatedAt: 99),
                session("deckhand", cwd: deckhand, updatedAt: 30),
                session("deckhand-2", cwd: deckhand, updatedAt: 10)
            ],
            isFavorite: { $0 == "deckhand-2" }
        )
        // the starred session is not the newest, and its project still goes to the top whole
        #expect(groups[0].path == deckhand)
        #expect(groups[0].sessions.count == 2)
        #expect(groups[0].hasFavorite)
        #expect(groups[1].hasFavorite == false)
    }

    @Test("below the favourites, the project that moved last comes first")
    func recencyOrder() {
        let groups = ProjectGroup.of(
            [
                session("old", cwd: deckhand, updatedAt: 10),
                session("new", cwd: quiz, updatedAt: 500)
            ],
            isFavorite: { _ in false }
        )
        #expect(groups.map(\.path) == [quiz, deckhand])
    }

    @Test("a path outside a home folder is shown exactly as the Mac spelled it")
    func foreignPath() {
        let group = ProjectGroup(path: "/opt/homebrew/src/thing", sessions: [], hasFavorite: false)
        #expect(group.name == "thing")
        #expect(group.parent == "/opt/homebrew/src")
    }

    @Test("a project sitting straight in the home folder still reads sensibly")
    func rightAtHome() {
        let group = ProjectGroup(path: "/Users/jurrejan/scratch", sessions: [], hasFavorite: false)
        #expect(group.name == "scratch")
        #expect(group.parent == "~")
    }

    @Test("no sessions is no groups")
    func empty() {
        #expect(ProjectGroup.of([], isFavorite: { _ in false }).isEmpty)
    }
}
