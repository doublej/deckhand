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

    @Test("the agents still going that no turn on the page started are the ones gathered up")
    func loose() {
        let drawn = Turn(role: "assistant", text: "delegating", timestamp: "1",
                         tools: [Tool(name: "Agent", detail: "look", toolId: "toolu_on_screen"),
                                 Tool(name: "Bash", detail: "ls", toolId: "toolu_bash")])
        let onScreen = Agent(id: "agent-a1", toolUseId: "toolu_on_screen", running: true)
        let offScreen = Agent(id: "agent-a2", toolUseId: "toolu_older", running: true,
                              updatedAt: 10)
        let newer = Agent(id: "agent-a3", toolUseId: "toolu_oldest", running: true, updatedAt: 20)
        let finished = Agent(id: "agent-a4", toolUseId: "toolu_done", running: false)
        let held = [onScreen, offScreen, newer, finished]
        // Only what is still going, only what the page does not already show, newest first —
        // the caller holds these in a dictionary, which has no order of its own.
        #expect(Agent.loose(held, notIn: [drawn]).map(\.id) == ["agent-a3", "agent-a2"])
        // With nothing drawn, every running agent is loose.
        #expect(Agent.loose(held, notIn: []).count == 3)
    }

    @Test("an agent with no tool call behind it is not claimed by a tool that has no id either")
    func looseWithoutIds() {
        // A daemon a version behind sends neither id. Matching empty against empty would hide
        // every running agent behind the first tool call on the page.
        let drawn = Turn(role: "assistant", text: "", timestamp: "1",
                         tools: [Tool(name: "Agent", detail: "look")])
        let orphan = Agent(id: "agent-a1", running: true)
        #expect(Agent.loose([orphan], notIn: [drawn]).map(\.id) == ["agent-a1"])
    }

    private func decoder() -> JSONDecoder {
        let made = JSONDecoder()
        made.keyDecodingStrategy = .convertFromSnakeCase
        return made
    }
}
