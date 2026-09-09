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

@Suite("Preferences")
struct PreferencesTests {
    @Test("starring and hiding survive a round trip")
    func roundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "deckhand.prefs.\(UUID().uuidString)"))
        var prefs = Preferences()
        prefs.toggleFavorite("warm-okapi")
        prefs.setHidden("binwatch", true)
        prefs.talkMode = .toggle
        prefs.save(to: defaults)

        let loaded = Preferences.load(from: defaults)
        #expect(loaded.isFavorite("warm-okapi"))
        #expect(loaded.isHidden("binwatch"))
        #expect(loaded.talkMode == .toggle)
    }

    @Test("the markdown reading choice is remembered, and on until it is turned off")
    func markdownFormatting() throws {
        let defaults = try #require(UserDefaults(suiteName: "deckhand.prefs.\(UUID().uuidString)"))
        // Nothing saved yet: a report opens formatted, because reading it is why you opened it.
        #expect(Preferences.load(from: defaults).formatsMarkdown)

        var prefs = Preferences()
        prefs.formatsMarkdown = false
        prefs.save(to: defaults)
        // And off stays off. `bool(forKey:)` would read a missing key as false and put the
        // default out of reach, which is why the load goes through `object(forKey:)`.
        #expect(Preferences.load(from: defaults).formatsMarkdown == false)
    }

    @Test("hiding a session drops it from favourites, since it cannot be both")
    func hidingClearsFavourite() {
        var prefs = Preferences(favorites: ["utt"])
        prefs.setHidden("utt", true)
        #expect(prefs.isFavorite("utt") == false)
        #expect(prefs.isHidden("utt"))
        prefs.setHidden("utt", false)
        #expect(prefs.isHidden("utt") == false)
    }

    @Test("starring twice unstars")
    func toggling() {
        var prefs = Preferences()
        prefs.toggleFavorite("a")
        prefs.toggleFavorite("a")
        #expect(prefs.favorites.isEmpty)
    }
}
