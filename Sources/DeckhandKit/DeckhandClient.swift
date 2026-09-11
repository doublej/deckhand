import Foundation

/// Talks to the deckhand daemon on the Mac. Every call carries the pairing token.
public struct DeckhandClient: Sendable {
    public let baseURL: URL
    public let token: String
    let urlSession: URLSession

    public init(baseURL: URL, token: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.urlSession = urlSession
    }

    public func health() async throws -> Health {
        try await get("health")
    }

    /// The live sessions, and what the listing says about the Mac itself — see `Listing`.
    public func sessions() async throws -> Listing {
        try await get("sessions")
    }

    /// What the session did since you last spoke. The Mac runs a small model to write it.
    /// The last briefing the Mac wrote for this session, and a nudge to write the next one.
    ///
    /// It answers off disk, so no long timeout: the Mac never makes the phone wait for a model.
    /// Asking is what moves this session to the front of the queue.
    public func summary(of sessionId: String) async throws -> Summary {
        try decode(try await send(request(.get, "sessions/\(sessionId)/summary")))
    }

    /// Every live session's last briefing in one call, which is what makes a cold start whole:
    /// a freshly installed app knows what the Mac knew, without buying any of it again.
    public func briefings() async throws -> [String: Summary] {
        struct Wrapper: Decodable { let briefings: [String: Summary] }
        let wrapper: Wrapper = try decode(try await send(request(.get, "briefings")))
        return wrapper.briefings
    }

    /// Everything this session touched that you could open and look at.
    public func files(of sessionId: String) async throws -> [Asset] {
        let body: [String: [Asset]] = try await get("sessions/\(sessionId)/files")
        return body["files"] ?? []
    }

    /// The slash commands and skills this session could be handed by name.
    ///
    /// Asked for when a picker opens rather than with the listing: there are getting on for two
    /// hundred of them on this Mac, most cards never want one, and they are files a person edits
    /// — so a copy kept on the phone would be a stale copy of something cheap to ask for.
    public func commands(of sessionId: String) async throws -> [SlashCommand] {
        let body: [String: [SlashCommand]] = try await get("sessions/\(sessionId)/commands")
        return body["commands"] ?? []
    }

    /// One of those files, saved to a local URL. The Mac serves only what that session's
    /// transcript named, so this is a way to see what it made and never a way to read its disk.
    ///
    /// To disk rather than into memory, because one of the three kinds is video: a rendered
    /// clip is routinely tens of megabytes, and AVPlayer wants a URL anyway. The caller owns
    /// the file and deletes it.
    ///
    /// ponytail: the whole file lands before anything is shown. Fine over a LAN; if a
    /// half-gigabyte clip ever needs to start playing at once, that is a ranged asset loader.
    public func download(_ asset: Asset, in sessionId: String) async throws -> URL {
        let escaped = asset.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var req = request(.get, "sessions/\(sessionId)/file?path=\(escaped)")
        req.timeoutInterval = 300
        let (temporary, response) = try await urlSession.download(for: req)
        try check(response, at: temporary)
        // The session's own temporary file is gone the moment this returns, and the extension
        // has to survive: AVFoundation picks its reader from it, exactly as utt does.
        let kept = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((asset.name as NSString).pathExtension)
        try FileManager.default.moveItem(at: temporary, to: kept)
        return kept
    }

    /// The same reading of a status code as `send`, for a body that went to disk.
    private func check(_ response: URLResponse, at file: URL) throws {
        guard let http = response as? HTTPURLResponse else { throw DeckhandError.badResponse }
        guard !(200..<300).contains(http.statusCode) else { return }
        let said = (try? Data(contentsOf: file)).flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
        try? FileManager.default.removeItem(at: file)
        switch http.statusCode {
        case 401: throw DeckhandError.unauthorized
        case 404: throw DeckhandError.notLive
        default: throw DeckhandError.http(http.statusCode, said)
        }
    }

    /// A page of the conversation. `before` counts backwards from the end — 0 is the tail, 25 is
    /// the twenty-five turns before that — because a transcript only grows at the end, so a
    /// cursor counted from there stays pointing at the same turn while the session keeps talking.
    public func turns(of sessionId: String, limit: Int = 8, before: Int = 0) async throws -> Rounds {
        try await get("sessions/\(sessionId)/turns?limit=\(limit)&before=\(before)")
    }

    /// Everything in the transcript, in order, one line per event and none of the syntax it is
    /// stored in. Every other reading in this app is an interpretation of the same file.
    public func raw(of sessionId: String, limit: Int = 1500) async throws -> [String] {
        struct Raw: Codable { var lines: [String] = [] }
        let answer: Raw = try await get("sessions/\(sessionId)/raw?limit=\(limit)")
        return answer.lines
    }

    /// Put words into a session, and name any pictures going with them. The other half of an
    /// upload the person asked to read first.
    public func say(
        _ text: String,
        to sessionId: String,
        route: DeliveryRoute,
        images: [String] = [],
        prepared: Bool = false
    ) async throws -> Delivery {
        // `prepared` says these words have already been through the Mac's filter chain and were
        // read on the card. Not an optimisation: prompt crafting rewrites rather than swaps, so a
        // second pass rewrites a prompt twice — and changing anything after somebody approved it
        // on the card would make the card a liar about what it sent.
        var req = request(.post,
                          "sessions/\(sessionId)/say?route=\(route.rawValue)&prepared=\(prepared)")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        struct Said: Encodable {
            let text: String
            let images: [String]
        }
        let body = try JSONEncoder().encode(Said(text: text, images: images))
        return try decode(try await send(req, body: body))
    }

    /// Hand a picture to the Mac and get back the path it was kept at.
    ///
    /// A path, because that is how an image reaches a session: the message names the file and
    /// the session reads it with its own tools. Nothing is pasted into a terminal.
    public func upload(image: Data, named name: String, to sessionId: String) async throws -> String {
        let boundary = "deckhand.\(UUID().uuidString)"
        var req = request(.post, "sessions/\(sessionId)/image")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        struct Kept: Decodable { let path: String }
        let kept: Kept = try decode(try await send(req, body: multipart(boundary: boundary,
                                                                       name: name,
                                                                       bytes: image)))
        return kept.path
    }

    /// Hand the Mac a token it can push a Lock Screen update to.
    ///
    /// Two kinds, and the daemon needs both. An `activity` token updates the card that is
    /// already on screen; a `start` token lets the daemon put a fresh one there when none is
    /// running, which is the only way this survives the system ending one after a few hours,
    /// or a reboot, or the app being force-quit.
    ///
    /// One card is one session, so an `activity` token says which session's card it addresses —
    /// the Mac keeps a slot per session and without this every card but the last one registered
    /// was unreachable, which is four cards stacked on a Lock Screen and only one of them alive.
    /// A `start` token belongs to the app rather than to any session and carries **no key at
    /// all**: the daemon's parameter defaults to empty, so an absent session is its start slot.
    public func register(pushToken: String, kind: String, session: String?) async throws {
        var req = request(.post, "live/token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var fields = ["token": pushToken, "kind": kind]
        if let session { fields["session"] = session }
        _ = try await send(req, body: try JSONEncoder().encode(fields))
    }

    /// Interrupt a run, compact the conversation, or clear it. Keystrokes into the session's
    /// own pane on the Mac, which is the only thing that can interrupt one.
    public func control(_ action: Control, of sessionId: String) async throws {
        _ = try await send(request(.post, "sessions/\(sessionId)/control?action=\(action.rawValue)"))
    }

    /// Give the session a new display name, by running Claude Code's own `/rename` in its pane.
    ///
    /// Answers whether its filter chain came with it. A chain is filed under the name, so the Mac
    /// is the only thing that can move one — and the phone says it happened, because a chain left
    /// behind at the old name is the same bug as a star that does not follow a rename.
    public func rename(_ sessionId: String, to name: String) async throws -> Bool {
        var req = request(.post, "sessions/\(sessionId)/name")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["name": name])
        let done: Renaming = try decode(try await send(req, body: body))
        return done.carriedFilters
    }

    /// Forget whatever the session's inbox still claims to hold. Nothing in Claude Code's own
    /// transcript is touched: the Mac draws a line beside it and reads the lane from there.
    public func clearQueue(of sessionId: String) async throws {
        _ = try await send(request(.post, "sessions/\(sessionId)/queue/clear"))
    }

    /// Bring the session's iTerm pane to the front on the Mac.
    public func focus(_ sessionId: String) async throws {
        _ = try await send(request(.post, "sessions/\(sessionId)/focus"))
    }

    // MARK: - plumbing

    // Whatever one of this type's other files reaches for is internal rather than private:
    // `DeckhandClient+Filters.swift` and `Artifacts.swift` are this same type in another file, and
    // a private member is private to its *file*, not to its type. Which members that is grows as
    // those files do, so the rule is written here rather than a list that goes stale — and none of
    // it leaves the module either way. Do not tidy one back to private: the error lands in the
    // other file, not in this one.

    enum Method: String { case get = "GET", post = "POST", put = "PUT" }

    func request(_ method: Method, _ path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: path, relativeTo: baseURL) ?? baseURL)
        req.httpMethod = method.rawValue
        req.setValue(token, forHTTPHeaderField: "x-deckhand-token")
        req.timeoutInterval = 20
        return req
    }

    /// Internal, not private: the `+Feature` splits in other files need it.
    func get<T: Decodable>(_ path: String) async throws -> T {
        try decode(try await send(request(.get, path)))
    }

    func send(_ req: URLRequest, body: Data? = nil) async throws -> Data {
        let (data, response): (Data, URLResponse)
        if let body {
            (data, response) = try await urlSession.upload(for: req, from: body)
        } else {
            (data, response) = try await urlSession.data(for: req)
        }
        guard let http = response as? HTTPURLResponse else { throw DeckhandError.badResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw DeckhandError.unauthorized
        case 404: throw DeckhandError.notLive
        default: throw DeckhandError.http(http.statusCode, String(bytes: data, encoding: .utf8) ?? "")
        }
    }

    func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    /// Internal, not private: `Clips/DeckhandClient+Clips.swift` is this same type.
    func multipart(boundary: String, clip: URL) throws -> Data {
        try multipart(boundary: boundary,
                      name: clip.lastPathComponent,
                      bytes: try Data(contentsOf: clip),
                      kind: "audio/m4a")
    }

    /// One file in one part. The Mac reads the kind off the filename, so the content type here
    /// only has to be present — it is the suffix that decides what is accepted.
    private func multipart(
        boundary: String,
        name: String,
        bytes: Data,
        kind: String = "application/octet-stream"
    ) throws -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n")
        data.append("Content-Type: \(kind)\r\n\r\n")
        data.append(bytes)
        data.append("\r\n--\(boundary)--\r\n")
        return data
    }
}

private extension Data {
    mutating func append(_ text: String) {
        append(Data(text.utf8))
    }
}

/// What the Mac says about a rename. Tolerant of a daemon that does not file chains by name yet:
/// no key means nothing was carried, which is the truth on that Mac.
private struct Renaming: Decodable {
    var carriedFilters = false

    enum CodingKeys: String, CodingKey {
        case carriedFilters
    }

    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        carriedFilters = try box.decodeIfPresent(Bool.self, forKey: .carriedFilters) ?? false
    }
}
