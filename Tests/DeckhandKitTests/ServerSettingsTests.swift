import Foundation
import Testing

@testable import DeckhandKit

@Suite("Server settings")
struct ServerSettingsTests {
    @Test("a bare hostname becomes a usable base URL")
    func bareHost() {
        #expect(ServerSettings(host: "m2-2.local").baseURL?.absoluteString == "http://m2-2.local:4180/")
    }

    @Test("host and port, spaces, and a full URL all normalise")
    func variants() {
        #expect(ServerSettings(host: " 192.168.178.180:4180 ").baseURL?.absoluteString
            == "http://192.168.178.180:4180/")
        #expect(ServerSettings(host: "http://m2-2.local:9000").baseURL?.absoluteString
            == "http://m2-2.local:9000/")
    }

    @Test("an empty host is not a server")
    func empty() {
        #expect(ServerSettings(host: "  ", token: "t").baseURL == nil)
        #expect(ServerSettings(host: "m2-2.local", token: "").isComplete == false)
        #expect(ServerSettings(host: "m2-2.local", token: "t").isComplete)
    }

    @Test("settings survive a round trip through defaults")
    func roundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "deckhand.tests.\(UUID().uuidString)"))
        ServerSettings(host: "mini.local:4180", token: "abc123").save(to: defaults)
        let loaded = ServerSettings.load(from: defaults)
        #expect(loaded == ServerSettings(host: "mini.local:4180", token: "abc123"))
    }
}
