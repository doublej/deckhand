import Foundation
import Testing

@testable import DeckhandKit

/// The project calls, as an extension of the client suite rather than a suite of their own.
///
/// `StubProtocol` holds its stubbed response and its last request in static storage, so two
/// suites stubbing the same transport run in parallel and answer each other's requests — which is
/// exactly what happened: a `/projects` body arrived at the `/sessions` test. Tests declared in an
/// extension belong to the extended suite, so these are covered by its `.serialized`.
extension ClientTests {
    private func stub() -> DeckhandClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return DeckhandClient(
            baseURL: URL(string: "http://m2-2.local:4180/")!,
            token: "tok",
            urlSession: URLSession(configuration: config)
        )
    }

    /// The one snake-case field on this wire. `touched_at` is what orders the whole list, so a
    /// decoder that quietly dropped it would leave four hundred rows in whatever order they came.
    @Test("decodes a /projects payload, touched_at included")
    func decodesProjects() async throws {
        StubProtocol.respond(with: Data("""
        {"source": "atlas", "projects": [
          {"name": "deckhand", "path": "/Users/jj/dev/multi-stack/deckhand",
           "relative": "multi-stack/deckhand", "description": "iOS remote", "kind": "swift",
           "touched_at": 1789010952.354, "live": 2, "trusted": true}
        ]}
        """.utf8))
        let catalog = try await stub().projects()
        let project = try #require(catalog.projects.first)
        #expect(project.touchedAt == 1789010952.354)
        // Machine and path, joined: the path alone stopped being unique when the picker grew a
        // second machine. A row with no host on it is this Mac, so its half is empty.
        #expect(project.id == "\n/Users/jj/dev/multi-stack/deckhand")
        #expect(project.line == "multi-stack/deckhand · iOS remote")
        #expect(StubProtocol.lastRequest?.url?.path == "/projects")
    }

    /// The path is what the body carries — a session is started in a folder, and
    /// two projects on this Mac can share a name (`app` appears three times) — and beside it the
    /// program the person chose, which a Mac left to guess would take to be Claude Code.
    @Test("starting a session posts the project's own path and the program chosen")
    func startsASession() async throws {
        // What comes back does not matter here: this is about what goes out, and the answer is
        // read through a `try?` so an unparseable body cannot hide the request that produced it.
        StubProtocol.respond(with: Data("{}".utf8))
        let project = Project(
            name: "shop", path: "/Users/jj/dev/web/shop", relative: "web/shop",
            description: "", kind: "node", touchedAt: 0, live: 0, trusted: true
        )
        _ = try? await stub().startSession(in: project, as: .codex)
        let body = try #require(StubProtocol.lastBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent["path"] == "/Users/jj/dev/web/shop")
        #expect(sent["provider"] == "codex")
        #expect(StubProtocol.lastRequest?.url?.path == "/projects/session")
        #expect(StubProtocol.lastRequest?.httpMethod == "POST")
    }

    /// Three rows: one from a Mac that predates Codex, one Codex thread, and one naming a program
    /// this phone has never heard of. All three have to arrive — a newer Mac costs a phone nothing.
    @Test("a session says which program it is, and no key or an unknown word is Claude Code")
    func decodesProvider() async throws {
        StubProtocol.respond(with: Data("""
        {"sessions":[
          {"session_id":"old","pid":1,"name":"a","cwd":"/c","folder":"c","status":"idle",
           "updated_at":1.0,"tty":"ttys001","pane":null},
          {"session_id":"cdx","pid":0,"name":"b","cwd":"/c","folder":"c","status":"busy",
           "updated_at":1.0,"tty":"","pane":null,"provider":"codex"},
          {"session_id":"new","pid":2,"name":"c","cwd":"/c","folder":"c","status":"idle",
           "updated_at":1.0,"tty":"ttys002","pane":null,"provider":"gemini"}]}
        """.utf8))
        let sessions = try await stub().sessions().sessions
        #expect(sessions.map(\.sessionId) == ["old", "cdx", "new"])
        #expect(sessions[0].provider == nil)
        #expect(!sessions[0].isCodex)
        #expect(sessions[1].provider == .codex)
        #expect(sessions[1].isCodex)
        #expect(sessions[2].provider == .claude)
        #expect(!sessions[2].isCodex)
    }

    /// What each program can be asked for, by capability, so no screen has to know which program
    /// answers which verb. Claude's controls need its pane; OpenCode's are its own API.
    @Test("each provider offers the controls its own Mac side can carry out")
    func capabilities() async throws {
        let found = try await threeProviders()
        let (claude, codex, opencode) = (found[0], found[1], found[2])
        #expect(opencode.provider == .opencode && opencode.isOpenCode)
        #expect([claude.providerWord, codex.providerWord, opencode.providerWord]
            == [nil, "CODEX", "OPENCODE"])
        #expect([claude.theirWord, codex.theirWord, opencode.theirWord]
            == ["CLAUDE", "CODEX", "OPENCODE"])
        // A Claude session with no pane can do nothing that is a keystroke.
        #expect(!claude.stops && !claude.compacts && !claude.renames)
        #expect(claude.endsByKeys && claude.hasContextTree && claude.isOnTheMac)
        #expect(codex.stops && !codex.compacts && !codex.renames && !codex.takesCommands)
        #expect(!codex.hasInbox && !codex.endsByKeys)
        #expect(opencode.stops && opencode.compacts && opencode.renames && opencode.takesCommands)
        #expect(opencode.hasInbox && !opencode.endsByKeys && !opencode.hasContextTree)
        #expect(!opencode.isOnTheMac)
    }

    /// A paneless Claude session, a Codex thread and an OpenCode session, off one listing.
    private func threeProviders() async throws -> [Session] {
        StubProtocol.respond(with: Data("""
        {"sessions":[
          {"session_id":"cc","pid":1,"name":"a","cwd":"/c","folder":"c","status":"idle",
           "updated_at":1.0,"tty":"ttys001","pane":null},
          {"session_id":"cdx","pid":0,"name":"b","cwd":"/c","folder":"c","status":"busy",
           "updated_at":1.0,"tty":"","pane":null,"provider":"codex"},
          {"session_id":"ses_1","pid":0,"name":"c","cwd":"/c","folder":"c","status":"busy",
           "updated_at":1.0,"tty":"","pane":null,"provider":"opencode"}]}
        """.utf8))
        return try await stub().sessions().sessions
    }
}

/// Everything a project row decides for itself, with no Mac involved.
@Suite("Projects", .serialized)
struct ProjectTests {
    /// atlas being down is not the same as there being no projects, and the picker says which.
    @Test("a list from atlas's cache says so, and atlas answering says nothing")
    func namesTheSource() {
        #expect(Catalog(projects: [], source: "atlas").caveat == nil)
        #expect(Catalog(projects: [], source: "atlas-cache").caveat?.contains("last scan") == true)
    }

    /// A row that cannot be started says so before it is pressed, not after.
    @Test("a row's note is what it can't do first, then what is already there")
    func saysWhatItIs() {
        #expect(make(trusted: false, live: 0).note == "not trusted yet")
        #expect(make(trusted: false, live: 3).note == "not trusted yet")
        #expect(make(trusted: true, live: 0).note == nil)
        #expect(make(trusted: true, live: 1).note == "1 session here")
        #expect(make(trusted: true, live: 4).note == "4 sessions here")
    }

    /// Four hundred rows means the field is the screen, and the field has to match on whichever
    /// of the three fields somebody happens to remember.
    @Test("a project matches on its name, its folder or what it is for")
    func matches() {
        let project = make(trusted: true, live: 0)
        #expect(project.matches(""))
        #expect(project.matches("deck"))
        #expect(project.matches("multi-stack"))
        #expect(project.matches("remote"))
        // Every word has to land, so two words narrow rather than widen.
        #expect(project.matches("deck remote"))
        #expect(!project.matches("deck banana"))
        #expect(!project.matches("banana"))
    }

    /// The third line of a row. Ordered, because a row that reorders its own facts between two
    /// projects is a row you have to read rather than scan.
    @Test("a row's facts are the short true things, and a dirty tree is a star")
    func statesTheFacts() {
        #expect(rich().facts == ["node", "sveltekit", "bun", "develop*", ":5188", "3 open",
                                 "utt.jurrejan.com"])
        // A project atlas could tell nothing about draws no third line at all, rather than a line
        // of empty separators.
        #expect(make(trusted: true, live: 0).facts == ["swift"])
        #expect(Project(name: "bare", path: "/b").facts.isEmpty)
    }

    /// A domain is the thing a person says out loud, and about four projects in a hundred have
    /// one — which is exactly what makes typing one the shortest way to the folder behind it.
    @Test("a project is findable by what it is built with and the name it answers on")
    func matchesTheNewFields() {
        #expect(rich().matches("sveltekit"))
        #expect(rich().matches("bun"))
        #expect(rich().matches("jurrejan.com"))
        #expect(rich().matches("develop"))
        // Two words still narrow, and they may land on different fields.
        #expect(rich().matches("sveltekit shop"))
        #expect(!rich().matches("sveltekit banana"))
    }

    /// A daemon that predates any of this sends eight keys, not sixteen. Every one of the rest
    /// has to decode as its empty value rather than throwing the listing away.
    @Test("an older Mac's payload still decodes")
    func decodesAnOlderPayload() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let old = try decoder.decode(Project.self, from: Data("""
        {"name": "shop", "path": "/Users/jj/dev/web/shop", "relative": "web/shop",
         "description": "", "kind": "node", "touched_at": 12.5, "live": 0, "trusted": true}
        """.utf8))
        #expect(old.touchedAt == 12.5)
        #expect(old.framework.isEmpty)
        #expect(old.domains.isEmpty)
        #expect(old.facts == ["node"])
    }

    @Test("a folder says which machine it is on, and a daemon that predates that says nothing")
    func machines() throws {
        let row = try JSONDecoder().decode(Project.self, from: Data("""
        {"name": "rig", "path": "C:\\\\dev\\\\thing", "machine": "fractal"}
        """.utf8))
        #expect(row.machine == "fractal")
        let old = try JSONDecoder().decode(Project.self, from: Data("""
        {"name": "shop", "path": "/Users/jj/dev/web/shop"}
        """.utf8))
        #expect(old.machine.isEmpty)  // no host on the row is this Mac, not an unknown one
    }

    @Test("the same path on two machines is two rows, not one")
    func identity() {
        let here = Project(name: "x", path: "/home/jurrejan/development/x")
        let there = Project(name: "x", path: "/home/jurrejan/development/x", machine: "ubuntu")
        #expect(here.id != there.id)
        #expect(Set([here, there]).count == 2)
    }

    @Test("typing a machine name narrows the picker to that machine")
    func searchingByMachine() {
        let rig = Project(name: "thing", path: "C:\\dev\\thing", machine: "fractal")
        let mine = Project(name: "thing", path: "/Users/jj/dev/thing")
        #expect(rig.matches("fractal"))
        #expect(!mine.matches("fractal"))
        // And it still narrows with the rest, rather than replacing them.
        #expect(rig.matches("fractal thing"))
    }

    private func rich() -> Project {
        Project(
            name: "shop", path: "/Users/jj/dev/web/shop", relative: "web/shop",
            description: "the shop", kind: "node", touchedAt: 0, live: 0, trusted: true,
            framework: "sveltekit", runner: "bun", branch: "develop", dirty: true,
            issues: 3, port: 5188, domains: ["utt.jurrejan.com"], sessions: 184
        )
    }

    private func make(trusted: Bool, live: Int) -> Project {
        Project(
            name: "deckhand",
            path: "/Users/jj/dev/multi-stack/deckhand",
            relative: "multi-stack/deckhand",
            description: "iOS remote",
            kind: "swift",
            touchedAt: 0,
            live: live,
            trusted: trusted
        )
    }
}
