import Foundation

/// Talks to the deckhand daemon on the Mac. Every call carries the pairing token.
public struct DeckhandClient: Sendable {
    public let baseURL: URL
    public let token: String
    private let urlSession: URLSession

    public init(baseURL: URL, token: String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.urlSession = urlSession
    }

    public func health() async throws -> Health {
        try await get("health")
    }

    public func sessions() async throws -> [Session] {
        let body: SessionList = try await get("sessions")
        return body.sessions
    }

    /// What the session did since you last spoke. The Mac runs a small model to write it.
    public func summary(of sessionId: String) async throws -> Summary {
        try await get("sessions/\(sessionId)/summary")
    }

    public func turns(of sessionId: String, limit: Int = 8) async throws -> [Turn] {
        let body: [String: [Turn]] = try await get("sessions/\(sessionId)/turns?limit=\(limit)")
        return body["turns"] ?? []
    }

    /// Bring the session's iTerm pane to the front on the Mac.
    public func focus(_ sessionId: String) async throws {
        _ = try await send(request(.post, "sessions/\(sessionId)/focus"))
    }

    /// Upload a recorded clip. The Mac stores it, transcribes it, and answers with the text.
    public func upload(clip: URL, to sessionId: String) async throws -> UploadReceipt {
        let boundary = "deckhand.\(UUID().uuidString)"
        var req = request(.post, "sessions/\(sessionId)/audio")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // The Mac transcribes before answering, and utt's first request loads the model.
        req.timeoutInterval = 200
        let data = try multipart(boundary: boundary, clip: clip)
        return try decode(try await send(req, body: data))
    }

    // MARK: - plumbing

    private enum Method: String { case get = "GET", post = "POST" }

    private func request(_ method: Method, _ path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: path, relativeTo: baseURL) ?? baseURL)
        req.httpMethod = method.rawValue
        req.setValue(token, forHTTPHeaderField: "x-deckhand-token")
        req.timeoutInterval = 20
        return req
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try decode(try await send(request(.get, path)))
    }

    private func send(_ req: URLRequest, body: Data? = nil) async throws -> Data {
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

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func multipart(boundary: String, clip: URL) throws -> Data {
        let name = clip.lastPathComponent
        var data = Data()
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n")
        data.append("Content-Type: audio/m4a\r\n\r\n")
        data.append(try Data(contentsOf: clip))
        data.append("\r\n--\(boundary)--\r\n")
        return data
    }
}

private struct SessionList: Decodable {
    let sessions: [Session]
}

private extension Data {
    mutating func append(_ text: String) {
        append(Data(text.utf8))
    }
}
