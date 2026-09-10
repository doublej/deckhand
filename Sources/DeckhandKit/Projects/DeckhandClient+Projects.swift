import Foundation

/// The two project calls, in their own file so each feature's calls are one file — the same seam
/// `DeckhandClient+Filters.swift` was split on, and for the same 300-line reason.
public extension DeckhandClient {
    /// Every project the Mac knows about, and which of its sources said so.
    ///
    /// One call, no paging: four or five hundred rows of seven short fields is a hundred-odd
    /// kilobytes over a LAN, and a picker that can only filter what it has already fetched is the
    /// one thing a picker must not be. The Mac caches this for a minute, so opening and closing
    /// the sheet twice costs it nothing.
    func projects() async throws -> Catalog {
        var req = request(.get, "projects")
        // Reading the catalogue can mean atlas has to answer first, and a cold atlas is slower
        // than a listing of sessions the daemon already holds.
        req.timeoutInterval = 30
        return try decode(try await send(req))
    }

    /// Open a terminal in that folder on the Mac and start Claude Code in it.
    ///
    /// Answers with the session itself rather than an acknowledgement, so the phone can go
    /// straight into the conversation instead of back to the rail to guess which row is new. The
    /// Mac waits for the session to write its own record before answering, which is why this is
    /// given far longer than any other call — and why a failure here is a sentence worth showing
    /// rather than a code: a folder Claude Code has never been trusted in is refused by name.
    func startSession(in project: Project) async throws -> Session {
        struct Started: Decodable { let session: Session }
        var req = request(.post, "projects/session")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        let body = try JSONEncoder().encode(["path": project.path])
        let started: Started = try decode(try await send(req, body: body))
        return started.session
    }
}
