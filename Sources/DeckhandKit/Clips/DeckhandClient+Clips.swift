import Foundation

/// A recorded clip going to the Mac. The same type as `DeckhandClient`, in another file.
///
/// Here rather than beside it for the reason `DeckhandClient+Filters.swift` exists: SwiftLint
/// caps a file at 300 lines and `DeckhandClient.swift` was sitting on it. `Sources/DeckhandKit/`
/// is also on `.quality.json`'s 16-file cap, so the split went into the folder that already
/// holds everything else about a clip's life.
public extension DeckhandClient {
    /// Upload a recorded clip. The Mac stores it, transcribes it, and answers with the text.
    ///
    /// `seconds` is how long the clip runs as this phone measured it. The Mac never opens the
    /// audio, so without it a line in `timings.jsonl` cannot say what a millisecond bought —
    /// which is the whole question a compression or speed experiment is asking.
    func upload(
        clip: URL,
        to sessionId: String,
        route: DeliveryRoute = .auto,
        deliver: Bool = true,
        seconds: Double? = nil
    ) async throws -> UploadReceipt {
        let boundary = "deckhand.\(UUID().uuidString)"
        var query = "route=\(route.rawValue)&deliver=\(deliver)"
        if let seconds { query += "&seconds=\(String(format: "%.3f", seconds))" }
        var req = request(.post, "sessions/\(sessionId)/audio?\(query)")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // The Mac transcribes before answering, and utt's first request loads the model.
        req.timeoutInterval = 200
        let data = try multipart(boundary: boundary, clip: clip)
        return try decode(try await send(req, body: data))
    }
}
