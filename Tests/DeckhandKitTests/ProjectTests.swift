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
        #expect(project.id == "/Users/jj/dev/multi-stack/deckhand")
        #expect(project.line == "multi-stack/deckhand · iOS remote")
        #expect(StubProtocol.lastRequest?.url?.path == "/projects")
    }

    /// The path is the identity, and the body carries it — a session is started in a folder, and
    /// two projects on this Mac can share a name (`app` appears three times).
    @Test("starting a session posts the project's own path")
    func startsASession() async throws {
        // What comes back does not matter here: this is about what goes out, and the answer is
        // read through a `try?` so an unparseable body cannot hide the request that produced it.
        StubProtocol.respond(with: Data("{}".utf8))
        let project = Project(
            name: "shop", path: "/Users/jj/dev/web/shop", relative: "web/shop",
            description: "", kind: "node", touchedAt: 0, live: 0, trusted: true
        )
        _ = try? await stub().startSession(in: project)
        let body = try #require(StubProtocol.lastBody)
        let sent = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(sent["path"] == "/Users/jj/dev/web/shop")
        #expect(StubProtocol.lastRequest?.url?.path == "/projects/session")
        #expect(StubProtocol.lastRequest?.httpMethod == "POST")
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
