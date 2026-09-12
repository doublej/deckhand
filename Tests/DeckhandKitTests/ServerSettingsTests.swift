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

    @Test("an https host keeps its own port, because that one is not the daemon")
    func offLan() {
        #expect(ServerSettings(host: "https://deckhand.jurrejan.com").baseURL?.absoluteString
            == "https://deckhand.jurrejan.com/")
        #expect(ServerSettings(host: "https://deckhand.jurrejan.com:8443").baseURL?.absoluteString
            == "https://deckhand.jurrejan.com:8443/")
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
    /// Every field, compared as the whole document rather than key by key.
    ///
    /// `Preferences` is `Equatable`, so one `==` asserts that no field is written by `save` and
    /// missed by `load` or the other way round — including any field added after this was
    /// written, which a list of per-key expectations would silently not cover. That gap is not
    /// hypothetical: a setting saved and never loaded looks exactly like a control that ignores
    /// you, and the person only finds out one relaunch later.
    @Test("every preference survives a round trip, not only the ones somebody thought of")
    func roundTrip() throws {
        let defaults = try #require(UserDefaults(suiteName: "deckhand.prefs.\(UUID().uuidString)"))
        var prefs = Preferences()
        prefs.toggleFavorite("warm-okapi")
        prefs.setHidden("binwatch", true)
        prefs.talkMode = .toggle
        prefs.route = .keyboard
        prefs.confirms = false
        prefs.formatsMarkdown = false
        prefs.linkWindow = 1800
        prefs.save(to: defaults)

        #expect(Preferences.load(from: defaults) == prefs)
    }

    /// Five minutes when nothing has been chosen, which is the number the daemon's own
    /// `within` defaults to — the phone sends the window, so the two cannot be different.
    @Test("the rail's window defaults to five minutes and is remembered once set")
    func linkWindow() throws {
        let defaults = try #require(UserDefaults(suiteName: "deckhand.prefs.\(UUID().uuidString)"))
        #expect(Preferences.load(from: defaults).linkWindow == 300)

        var prefs = Preferences()
        prefs.linkWindow = 60
        prefs.save(to: defaults)
        #expect(Preferences.load(from: defaults).linkWindow == 60)
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

/// What this Mac has been set to do, and the one decoding trap that would quietly lose it.
///
/// No stub in here: all of it is pure, so it stays out of `ClientTests` and its serialization.
@Suite("Wants")
struct WantsTests {
    private func document(_ path: String) -> Settings {
        var over = Overrides()
        over.chase = false
        over.summaryModel = "claude-opus-5"
        return Settings(everywhere: Wants(finished: true, slips: false, chase: true),
                        projects: [path: over])
    }

    /// Per key, not per object. This is the whole point of the override shape: a folder given one
    /// answer keeps every other one, and goes on following the Mac when the Mac changes.
    @Test("a folder overrides one answer and follows the Mac for the rest")
    func resolves() {
        let here = document("/a").resolved(for: "/a")
        #expect(here.chase == false)
        #expect(here.summaryModel == "claude-opus-5")
        #expect(here.finished == true)
        #expect(here.slips == false)
        // A folder nobody has an opinion about is the global answer, whole.
        #expect(document("/a").resolved(for: "/b").chase == true)
        #expect(document("/a").overridden("/b") == false)
        #expect(document("/a").overridden("/a") == true)
    }

    /// `convertFromSnakeCase` rewrites **dictionary keys** as well as struct keys, and the keys of
    /// `projects` are folder paths. This tree has `_archive` and `_sandbox` in it, so the trap is
    /// not hypothetical: the converter renames the folder and the override filed under it is
    /// gone.
    ///
    /// Measured, and it is worse *and* better than expected. Spelling the two snake-case fields
    /// out in `CodingKeys` means the converting decoder cannot find `session_model` either, so it
    /// throws rather than quietly handing back a document with the overrides missing. Both facts
    /// are asserted, because the loud failure is what the spelled-out keys buy: without them this
    /// would decode cleanly and lose the folder in silence.
    @Test("a folder path with an underscore survives decoding")
    func keepsPaths() throws {
        let path = "/Users/jj/dev/_sandbox/my_thing"
        let body = Data("""
        {"finished": false, "slips": true, "called": true, "chase": true, "subagents": false,
         "session_model": "opus", "summary_model": "",
         "projects": {"\(path)": {"chase": false}},
         "offers": {"session": ["opus"], "summary": ["claude-opus-5"]}}
        """.utf8)
        let settings = try JSONDecoder().decode(Settings.self, from: body)
        #expect(settings.projects[path]?.chase == false)
        #expect(settings.everywhere.sessionModel == "opus")
        #expect(settings.everywhere.finished == false)
        #expect(settings.offers.summary == ["claude-opus-5"])

        let converting = JSONDecoder()
        converting.keyDecodingStrategy = .convertFromSnakeCase
        #expect(throws: DecodingError.self) {
            try converting.decode(Settings.self, from: body)
        }
    }

    /// The Mac drops an override that says nothing, so the phone must not draw a folder as
    /// configured on the strength of an empty object.
    @Test("an override that says nothing is not an override")
    func emptyIsNothing() {
        #expect(Overrides().isEmpty)
        var one = Overrides()
        one.slips = true
        #expect(!one.isEmpty)
    }

    /// The global answers sit at the top level of the same object, so a round trip has to put
    /// them back there rather than nesting them under a key the Mac has never heard of.
    @Test("the document goes back out the shape it came in")
    func roundTrips() throws {
        let sent = try JSONEncoder().encode(document("/a"))
        let back = try JSONDecoder().decode(Settings.self, from: sent)
        #expect(back.everywhere.slips == false)
        #expect(back.projects["/a"]?.summaryModel == "claude-opus-5")
        let raw = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(raw["summary_model"] as? String == "")
        #expect(raw["finished"] as? Bool == true)
    }
}
