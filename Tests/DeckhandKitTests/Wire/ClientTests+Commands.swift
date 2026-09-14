import Foundation
import Testing

@testable import DeckhandKit

/// Running a project's `just` recipes from the phone.
///
/// An `extension ClientTests` in the `Wire` folder rather than a suite of its own, for the reason
/// `ClientTests+Turns.swift` gives at the top of it: `StubProtocol` is static, so a second suite
/// stubbing the same transport answers the first one's requests.
extension ClientTests {
    private var project: Project { Project(name: "deckhand", path: "/Users/jj/dev/deckhand") }

    @Test("recipes come back grouped, with what each one needs")
    func decodesRecipes() async throws {
        StubProtocol.respond(with: Data("""
        {"has_justfile": true, "recipes": [
            {"name": "daemon", "doc": "Run the daemon", "group": "develop", "needs_args": false},
            {"name": "build", "doc": "", "group": "", "needs_args": true}
        ]}
        """.utf8))
        let listing = try await client().recipes(for: project)
        #expect(listing.hasJustfile)
        #expect(listing.recipes.map(\.name) == ["daemon", "build"])
        #expect(listing.recipes[0].group == "develop")
        #expect(listing.recipes[1].needsArgs)
        #expect(StubProtocol.lastRequest?.url?.path == "/projects/commands")
        #expect(StubProtocol.lastRequest?.url?.query == "path=/Users/jj/dev/deckhand")
    }

    @Test("a folder with no justfile offers nothing")
    func decodesNoJustfile() async throws {
        StubProtocol.respond(with: Data(#"{"has_justfile": false, "recipes": []}"#.utf8))
        let listing = try await client().recipes(for: project)
        #expect(listing.hasJustfile == false)
        #expect(listing.recipes.isEmpty)
    }

    @Test("running a recipe posts the project and the recipe's own name")
    func runsARecipe() async throws {
        StubProtocol.respond(with: Data(#"{"pid": 4242, "started_at": 100}"#.utf8))
        try await client().run(Recipe(name: "daemon"), in: project)
        #expect(StubProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubProtocol.lastRequest?.url?.path == "/projects/commands/run")
        let body = try #require(StubProtocol.lastBody)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(sent?["path"] == "/Users/jj/dev/deckhand")
        #expect(sent?["recipe"] == "daemon")
    }

    @Test("stopping answers whether anything was actually running")
    func stopsARecipe() async throws {
        StubProtocol.respond(with: Data(#"{"stopped": true}"#.utf8))
        let stopped = try await client().stop(Recipe(name: "daemon"), in: project)
        #expect(stopped)
        #expect(StubProtocol.lastRequest?.url?.path == "/projects/commands/stop")
    }

    @Test("status carries whether it is still running, its exit code, and the tail of its output")
    func decodesStatus() async throws {
        StubProtocol.respond(with: Data("""
        {"running": false, "pid": 4242, "started_at": 100, "exit_code": 0, "log": "daemon up\\n"}
        """.utf8))
        let status = try await client().status(of: Recipe(name: "daemon"), in: project)
        #expect(status.running == false)
        #expect(status.exitCode == 0)
        #expect(status.verdict == "finished")
        #expect(status.log == "daemon up\n")
        #expect(StubProtocol.lastRequest?.url?.path == "/projects/commands/status")
    }

    @Test("a recipe still running has no verdict yet")
    func stillRunningHasNoVerdict() async throws {
        StubProtocol.respond(with: Data("""
        {"running": true, "pid": 4242, "started_at": 100, "exit_code": null, "log": ""}
        """.utf8))
        let status = try await client().status(of: Recipe(name: "daemon"), in: project)
        #expect(status.running)
        #expect(status.verdict == nil)
    }
}
