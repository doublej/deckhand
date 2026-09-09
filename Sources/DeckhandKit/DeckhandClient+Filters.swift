import Foundation

/// The two filter calls, in their own file so each feature's calls are one file.
///
/// `DeckhandClient.swift` reached its 300-line gate and this is the seam that costs the least: a
/// branch adding calls of its own lands in the core file without touching this one, and a split
/// down the middle of the type would have made that a conflict instead. The transport it leans on
/// is `internal` rather than `private` for the one Swift reason — a private member is private to
/// its *file*, and this is the same type in a second one. Nothing left the module.
public extension DeckhandClient {
    /// What this Mac can do to words on their way into this session, and the chain it runs now.
    ///
    /// One call for the whole page: `known` is the description the screen draws itself from, and
    /// the phone holds no list of filters of its own — which is what lets a filter added on the
    /// Mac this afternoon appear on this page this afternoon, with no build of the app.
    func filters(of sessionId: String) async throws -> (known: [Filter], steps: [FilterStep]) {
        let offered: FilterOffer = try literally(
            try await send(request(.get, "sessions/\(sessionId)/filters"))
        )
        return (offered.known, offered.steps)
    }

    /// Save this session's chain, and take the Mac's own reading of it back. What it answers with
    /// is what it will run, so the screen follows that rather than what it just sent.
    ///
    /// A chain is filed on the Mac under the session's **name**, not its id: an id is new every
    /// time Claude Code restarts in that pane, and what was asked for is a setting belonging to the
    /// terminal. The id in this path is only how the Mac works out which name that is.
    func saveFilters(_ steps: [FilterStep], of sessionId: String) async throws -> [FilterStep] {
        var req = request(.put, "sessions/\(sessionId)/filters")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(FilterChain(steps: steps))
        let saved: FilterChain = try literally(try await send(req, body: body))
        return saved.steps
    }

    /// The same decode with the keys left exactly as they arrived.
    ///
    /// `.convertFromSnakeCase` rewrites the keys of a dictionary as well as those of a struct, and
    /// a step's `settings` is a dictionary the filter owns: a filter taking `max_words` would be
    /// handed back `maxWords`, which is a setting it has never heard of. Nothing on the filters
    /// wire is snake case, so there is nothing to convert either.
    private func literally<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
