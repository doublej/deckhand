import Foundation
import Testing

@testable import DeckhandKit

@Suite("Subagents")
struct AgentTests {
    @Test("an agent decodes, and a daemon that predates the route sends none of it")
    func decoding() throws {
        let agent = try decoder().decode(Agent.self, from: Data("""
        {"id": "agent-a1", "tool_use_id": "toolu_1", "kind": "Explore",
         "description": "Survey the backend", "model": "opus", "depth": 1,
         "running": true, "turns": 3, "steps": 17, "updated_at": 12.5}
        """.utf8))
        #expect(agent.toolUseId == "toolu_1")   // snake_case, via the client's own strategy
        #expect(agent.updatedAt == 12.5)
        #expect(agent.running)
        #expect(agent.title == "Survey the backend")
        #expect(agent.line == "Explore · opus · 17 steps")
        let bare = try decoder().decode(Agent.self, from: Data(#"{"id": "agent-a2"}"#.utf8))
        #expect(bare.toolUseId.isEmpty)
        #expect(bare.depth == 1)
        #expect(bare.title == "agent")  // no description and no kind is still a row
    }

    @Test("a tool says whether it started an agent, and carries the id that finds it")
    func theJoin() {
        let started = Tool(name: "Agent", detail: "look around", toolId: "toolu_1")
        #expect(started.isAgent)
        #expect(started.id == "toolu_1")
        #expect(Tool(name: "Task", detail: "old spelling").isAgent)
        #expect(!Tool(name: "Bash", detail: "ls").isAgent)
        // A daemon a version behind sends no id, and the old identity still holds a list together.
        #expect(Tool(name: "Bash", detail: "ls").id == "Bashlstrue")
    }

    private func decoder() -> JSONDecoder {
        let made = JSONDecoder()
        made.keyDecodingStrategy = .convertFromSnakeCase
        return made
    }
}
