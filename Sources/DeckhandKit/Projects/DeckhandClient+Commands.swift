import Foundation

/// Running a project's own `just` recipes from the phone — a deploy, a server, anything else its
/// justfile knows how to do. In its own file for the reason `DeckhandClient+Projects.swift` gives:
/// each feature's calls are one file.
public extension DeckhandClient {
    /// The recipes that project's folder offers, or an empty listing when it has no justfile.
    func recipes(for project: Project) async throws -> RecipeListing {
        try await get("projects/commands?path=\(escaped(project.path))")
    }

    /// Start a recipe in that folder. Answers as soon as it is spawned — a deploy can run for
    /// minutes, so the caller polls `commandStatus` for how it is doing rather than holding this
    /// call open for however long that takes.
    func run(_ recipe: Recipe, in project: Project) async throws {
        var req = request(.post, "projects/commands/run")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["path": project.path, "recipe": recipe.name])
        _ = try await send(req, body: body)
    }

    /// Kill whatever is running under that recipe. `true` when something was actually stopped.
    @discardableResult
    func stop(_ recipe: Recipe, in project: Project) async throws -> Bool {
        struct Stopped: Decodable { let stopped: Bool }
        var req = request(.post, "projects/commands/stop")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["path": project.path, "recipe": recipe.name])
        let stopped: Stopped = try decode(try await send(req, body: body))
        return stopped.stopped
    }

    /// Whether that recipe is still running, and the tail of what it has said. Meant to be polled
    /// while a row is showing "running" — see `RecipeListing`.
    func status(of recipe: Recipe, in project: Project) async throws -> CommandStatus {
        try await get(
            "projects/commands/status?path=\(escaped(project.path))&recipe=\(escaped(recipe.name))"
        )
    }

    /// `download(_:in:)` in the main client file escapes a path the same way; this stays private
    /// to this file rather than becoming a third shared copy of one line.
    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    }
}
