import Foundation
import Testing

@testable import DeckhandKit

@Suite("Deckhand client", .serialized)
struct ClientTests {
    private func client() -> DeckhandClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return DeckhandClient(
            baseURL: URL(string: "http://m2-2.local:4180/")!,
            token: "tok",
            urlSession: URLSession(configuration: config)
        )
    }

    @Test("decodes a real /sessions payload from the daemon")
    func decodesSessions() async throws {
        StubProtocol.respond(with: fixture("sessions"))
        let sessions = try await client().sessions()
        #expect(sessions.count == 3)
        let first = try #require(sessions.first)
        #expect(first.name == "warm-okapi")
        #expect(first.folder == "the-ultimate-music-quiz")
        #expect(first.isBusy)
        #expect(first.pane?.tabId == "180")
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "x-deckhand-token") == "tok")
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions")
    }

    @Test("decodes a real /turns payload")
    func decodesTurns() async throws {
        StubProtocol.respond(with: fixture("turns"))
        let turns = try await client().turns(of: "809bbb83-b4dd-4680-8109-de8c18cf7d69", limit: 4)
        #expect(turns.count == 2)
        #expect(turns.allSatisfy { $0.role == "assistant" })
        #expect(StubProtocol.lastRequest?.url?.query == "limit=4")
    }

    @Test("an upload carries the clip bytes as multipart")
    func uploadsClip() async throws {
        let clip = FileManager.default.temporaryDirectory.appendingPathComponent("clip.m4a")
        try Data("pretend audio".utf8).write(to: clip)
        StubProtocol.respond(with: Data("""
        {"path":"/tmp/x.m4a","bytes":13,"received_at":1.0,"transcript":null}
        """.utf8), status: 201)

        let receipt = try await client().upload(clip: clip, to: "sid")
        #expect(receipt.bytes == 13)
        #expect(receipt.transcript == nil)
        let body = try #require(StubProtocol.lastBody)
        let text = try #require(String(bytes: body, encoding: .utf8))
        #expect(text.contains("filename=\"clip.m4a\""))
        #expect(text.contains("pretend audio"))
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/audio")
    }

    @Test("a bad token surfaces as unauthorized, a dead session as notLive")
    func errors() async throws {
        StubProtocol.respond(with: Data("{}".utf8), status: 401)
        await #expect(throws: DeckhandError.unauthorized) { try await client().sessions() }
        StubProtocol.respond(with: Data("{}".utf8), status: 404)
        await #expect(throws: DeckhandError.notLive) { try await client().turns(of: "gone") }
    }

    private func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")
        return (try? Data(contentsOf: url!)) ?? Data()
    }
}

/// Answers every request with a canned response and remembers what was asked.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    static func respond(with data: Data, status code: Int = 200) {
        body = data
        status = code
        lastRequest = nil
        lastBody = nil
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            return data
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
