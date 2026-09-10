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
        let listing = try await client().sessions()
        #expect(listing.sessions.count == 3)
        let first = try #require(listing.sessions.first)
        #expect(first.name == "warm-okapi")
        #expect(first.folder == "the-ultimate-music-quiz")
        #expect(first.isBusy)
        #expect(first.pane?.tabId == "180")
        // The fixture predates artifacts, which is the version-skew case: no keys, no pages.
        #expect(first.waitingPages == 0)
        #expect(first.pages == 0)
        // And predates the week and the model, which read the same way: nothing to say.
        #expect(first.family == nil)
        #expect(listing.week == nil)
        #expect(StubProtocol.lastRequest?.value(forHTTPHeaderField: "x-deckhand-token") == "tok")
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions")
    }

    @Test("a session says how many of its pages are waiting and how many are answered")
    func decodesWaitingPages() async throws {
        StubProtocol.respond(with: Data("""
        {"sessions":[{"session_id":"sid","pid":1,"name":"warm-okapi","cwd":"/Users/jj/dev/shop",
          "folder":"shop","status":"idle","updated_at":1.0,"tty":"ttys001","pane":null,
          "artifacts_waiting":2,"artifacts_answered":4}]}
        """.utf8))
        let session = try #require(try await client().sessions().sessions.first)
        #expect(session.waitingPages == 2)
        #expect(session.answeredPages == 4)
        #expect(session.pages == 6)
    }

    @Test("the listing carries the week and what answered each session's last request")
    func decodesWeekAndModel() async throws {
        StubProtocol.respond(with: Data("""
        {"sessions":[{"session_id":"sid","pid":1,"name":"warm-okapi","cwd":"/Users/jj/dev/shop",
          "folder":"shop","status":"idle","updated_at":1.0,"tty":"ttys001","pane":null,
          "model":"claude-sonnet-5","effort":"xhigh"}],
         "week":{"pct_used":152,"pct_elapsed":51,"days_remaining":3.5}}
        """.utf8))
        let listing = try await client().sessions()
        #expect(listing.week?.pctUsed == 152)
        #expect(listing.week?.line == "152% · 3d")
        #expect(listing.sessions.first?.family == "sonnet")
        #expect(listing.sessions.first?.effort == "xhigh")
    }

    @Test("a week this app cannot read costs the sessions nothing")
    func tolerateBrokenWeek() async throws {
        StubProtocol.respond(with: Data("""
        {"sessions":[{"session_id":"sid","pid":1,"name":"warm-okapi","cwd":"/Users/jj/dev/shop",
          "folder":"shop","status":"idle","updated_at":1.0,"tty":"ttys001","pane":null}],
         "week":{"pct_used":"most of it"}}
        """.utf8))
        let listing = try await client().sessions()
        #expect(listing.week == nil)
        #expect(listing.sessions.count == 1)
    }

    @Test("decodes a real /turns payload")
    func decodesTurns() async throws {
        StubProtocol.respond(with: fixture("turns"))
        let rounds = try await client().turns(of: "809bbb83-b4dd-4680-8109-de8c18cf7d69", limit: 4)
        #expect(rounds.turns.count == 2)
        #expect(rounds.turns.allSatisfy { $0.role == "assistant" })
        // The fixture predates the inbox, which is the version-skew case: no key, no queue.
        #expect(rounds.queued.isEmpty)
        #expect(StubProtocol.lastRequest?.url?.query == "limit=4")
    }

    @Test("an upload carries the clip bytes as multipart")
    func uploadsClip() async throws {
        let clip = FileManager.default.temporaryDirectory.appendingPathComponent("clip.m4a")
        try Data("pretend audio".utf8).write(to: clip)
        StubProtocol.respond(with: Data("""
        {"path":"/tmp/x.m4a","bytes":13,"received_at":1.0,"transcript":"Testing, one, two, three.",
         "transcript_error":null,"delivered":true,"delivered_by":"keyboard","delivery_error":null}
        """.utf8), status: 201)

        let receipt = try await client().upload(clip: clip, to: "sid")
        #expect(receipt.bytes == 13)
        #expect(receipt.transcript == "Testing, one, two, three.")
        #expect(receipt.transcriptError == nil)
        #expect(receipt.delivered)
        #expect(receipt.deliveredBy == "keyboard")
        let body = try #require(StubProtocol.lastBody)
        let text = try #require(String(bytes: body, encoding: .utf8))
        #expect(text.contains("filename=\"clip.m4a\""))
        #expect(text.contains("pretend audio"))
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/audio")
        #expect(StubProtocol.lastRequest?.url?.query == "route=auto&deliver=true")
    }

    @Test("a clip can be transcribed without being delivered")
    func holdsForReview() async throws {
        let clip = FileManager.default.temporaryDirectory.appendingPathComponent("clip.m4a")
        try Data("pretend audio".utf8).write(to: clip)
        StubProtocol.respond(with: Data("""
        {"path":"/tmp/x.m4a","bytes":13,"received_at":1.0,"transcript":"read me first",
         "transcript_error":null,"delivered":false,"delivered_by":null,"delivery_error":null}
        """.utf8), status: 201)

        let receipt = try await client().upload(clip: clip, to: "sid", deliver: false)
        #expect(receipt.transcript == "read me first")
        #expect(!receipt.delivered)
        #expect(StubProtocol.lastRequest?.url?.query == "route=auto&deliver=false")
    }

    @Test("saying something sends the text and reports which route took it")
    func saysText() async throws {
        StubProtocol.respond(with: Data("""
        {"delivered":true,"delivered_by":"keyboard","delivery_error":null}
        """.utf8), status: 200)

        let sent = try await client().say("run the tests", to: "sid", route: .keyboard)
        #expect(sent.delivered)
        #expect(sent.deliveredBy == "keyboard")
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/say")
        // Unprepared by default: words that did not come off a review card have not been past
        // the Mac's filter chain, so it still gets its turn at them.
        #expect(StubProtocol.lastRequest?.url?.query == "route=keyboard&prepared=false")
        let body = try #require(StubProtocol.lastBody)
        #expect(try #require(String(bytes: body, encoding: .utf8)).contains("run the tests"))
    }

    @Test("one session's filters arrive with the keys the filters own untouched")
    func decodesFilters() async throws {
        // The session's own route carries `known` as well as the chain, so the page it draws is
        // one request. The extra `session` key is the Mac naming the terminal it filed this under.
        StubProtocol.respond(with: Data("""
        {"session":"warm-okapi",
         "known":[{"name":"words","title":"Word replacement","summary":"Swaps words",
                   "fields":[{"key":"pairs","label":"Replacements","kind":"pairs",
                              "default":[],"hint":""}]}],
         "steps":[{"filter":"words","on":true,"settings":{"max_words":12}}]}
        """.utf8))
        let offered = try await client().filters(of: "sid")
        #expect(offered.known.first?.fields.first?.kind == .pairs)
        // The one way this breaks: the snake-case key strategy reaching a dictionary the filter
        // owns. `max_words` is the filter's own word and has to come back as it left.
        #expect(offered.steps.first?.settings["max_words"] == .int(12))
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/filters")
    }

    @Test("saving a session's chain PUTs it and reads back what the Mac will actually run")
    func savesFilters() async throws {
        StubProtocol.respond(with: Data("""
        {"session":"warm-okapi","steps":[{"filter":"words","on":false,"settings":{}}]}
        """.utf8))
        let step = FilterStep(filter: "words", isOn: true, settings: ["max_words": .int(12)])
        let saved = try await client().saveFilters([step], of: "sid")
        #expect(saved.first?.isOn == false)
        #expect(StubProtocol.lastRequest?.httpMethod == "PUT")
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/filters")
        let body = try #require(StubProtocol.lastBody)
        let text = try #require(String(bytes: body, encoding: .utf8))
        #expect(text.contains("\"max_words\":12"))
        #expect(text.contains("\"on\":true"))
    }

    @Test("a rename says whether the chain came with it")
    func carriesTheChainOnRename() async throws {
        StubProtocol.respond(with: Data("""
        {"renamed":"cold-otter","was":"warm-okapi","carried_filters":true}
        """.utf8))
        #expect(try await client().rename("sid", to: "cold-otter"))
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/name")
        // A Mac that does not file chains by name yet says nothing, and nothing is the truth
        // there — not an error, and not a claim that something moved.
        StubProtocol.respond(with: Data(#"{"renamed":"cold-otter","was":"warm-okapi"}"#.utf8))
        #expect(try await client().rename("sid", to: "cold-otter") == false)
    }

    @Test("a bad token surfaces as unauthorized, a dead session as notLive")
    func errors() async throws {
        StubProtocol.respond(with: Data("{}".utf8), status: 401)
        await #expect(throws: DeckhandError.unauthorized) { try await client().sessions() }
        StubProtocol.respond(with: Data("{}".utf8), status: 404)
        await #expect(throws: DeckhandError.notLive) { try await client().turns(of: "gone") }
    }

    @Test("the artifact listing decodes, and a daemon without the route means none rather than an error")
    func listsArtifacts() async throws {
        StubProtocol.respond(with: Data("""
        {"artifacts":[{"id":"release-check","title":"Release check",
                       "modified":1757500000.0,"answered":false}]}
        """.utf8))
        let found = try await client().artifacts(of: "sid")
        #expect(found.first?.title == "Release check")
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/artifacts")
        // The version-skew case, and the reason this is not a thrown error: a daemon that
        // predates artifacts answers 404 to the route, exactly as it does for a dead session.
        StubProtocol.respond(with: Data(#"{"detail":"Not Found"}"#.utf8), status: 404)
        #expect(try await client().artifacts(of: "sid").isEmpty)
    }

    @Test("a page is fetched by its slug in the path, and arrives as the HTML it is")
    func fetchesAPage() async throws {
        StubProtocol.respond(with: Data("<!doctype html><title>Pick one</title>".utf8))
        let html = try await client().page(of: "release check", in: "sid")
        #expect(html.hasPrefix("<!doctype html>"))
        // A slug is a filename an agent picked, so it is escaped as a path segment rather than
        // trusted: a space in one would otherwise make the URL itself invalid.
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/artifacts/release check")
        #expect(StubProtocol.lastRequest?.url?.absoluteString.hasSuffix("release%20check") == true)
    }

    @Test("an answer travels as JSON the phone has parsed, never as the text it was handed")
    func answersAnArtifact() async throws {
        StubProtocol.respond(with: Data(#"{"delivered":true,"delivered_by":"socket"}"#.utf8))
        let sent = try await client().answer("which-branch", in: "sid",
                                            valueJSON: #"{"branch":"develop","sure":true}"#,
                                            route: .socket)
        #expect(sent.went)
        #expect(sent.deliveredBy == "socket")
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/artifacts/which-branch/answer")
        // The person's own chosen route, the same one speaking travels by.
        #expect(StubProtocol.lastRequest?.url?.query == "route=socket")
        let body = try #require(StubProtocol.lastBody)
        let text = try #require(String(bytes: body, encoding: .utf8))
        #expect(text.contains(#""branch":"develop""#))
    }

    @Test("a page that answers with something that is not JSON gets nowhere near the Mac")
    func refusesRubbish() async throws {
        StubProtocol.respond(with: Data(#"{"delivered":true}"#.utf8))
        await #expect(throws: (any Error).self) {
            try await client().answer("x", in: "sid", valueJSON: "not json at all")
        }
        #expect(StubProtocol.lastRequest == nil)
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
