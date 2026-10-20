import Foundation
import Testing

@testable import DeckhandKit

/// Which URL a tap opens, and what the page and its square say. The Mac decided everything else.
@Suite struct AddressesTests {
    @Test("a loopback address opens on the LAN address the Mac found, then atlas's hostname")
    func opensWhatWorksFromThePhone() {
        let lan = Address(origin: "http://localhost:5173", paths: ["/admin"], reach: "home",
                          lanUrl: "http://192.168.1.2:5173/admin")
        #expect(Addresses.opens(lan)?.absoluteString == "http://192.168.1.2:5173/admin")
        let atlas = Address(origin: "http://localhost:4109", reach: "mac",
                            atlas: Registered(name: "eink", local: "https://web-eink.atlas.local.jurrejan.com"))
        #expect(Addresses.opens(atlas)?.absoluteString == "https://web-eink.atlas.local.jurrejan.com")
        #expect(Addresses.choices(atlas).map(\.absoluteString) == [
            "https://web-eink.atlas.local.jurrejan.com", "http://localhost:4109"])
    }

    @Test("rows fall into the Mac's three tiers, an unknown word with the rest")
    func splitsIntoTiers() {
        let rows = [Address(origin: "https://a.nl", tier: "rest"), Address(origin: "https://b.nl"),
                    Address(origin: "https://c.nl", tier: "recent"), Address(origin: "https://d.nl", tier: "odd")]
        let tiers = Addresses.tiers(rows)
        #expect(tiers.important.map(\.origin) == ["https://b.nl"])
        #expect(tiers.recent.map(\.origin) == ["https://c.nl"])
        #expect(tiers.rest.map(\.origin) == ["https://a.nl", "https://d.nl"])
    }

    @Test("only a problem gets words, and the reason carries how long ago")
    func saysOnlyWhatIsWrong() throws {
        #expect(Addresses.problem(Address(origin: "https://a.nl")) == nil)
        #expect(Addresses.problem(Address(origin: "https://a.nl", state: "fails", status: 502)) == "Error 502")
        #expect(Addresses.problem(Address(origin: "https://a.nl", state: "locked", note: "asks for a password"))
            == "Asks for a password")
        let now = try #require(Addresses.date("2026-10-20T12:00:00.000Z"))
        let shared = Address(origin: "https://a.nl", why: "Staging", lastAt: "2026-10-20T11:48:00.000Z")
        #expect(Addresses.why(shared, now: now).hasPrefix("Staging · "))
        #expect(Addresses.why(Address(origin: "https://a.nl", why: "Staging"), now: now) == "Staging")
    }

    @Test("the square counts what is worth a look, and says so in words when there is nothing")
    func countsWhatMatters() {
        #expect(Addresses.count(nil) == "…")
        #expect(Addresses.count([]) == "None yet")
        let rows = [Address(origin: "https://www.a.nl"), Address(origin: "https://b.nl", tier: "rest")]
        #expect(Addresses.count(rows) == "1 to look at")
        #expect(Addresses.count([rows[1]]) == "1 found")
        #expect(Addresses.worth(rows) == ["a.nl", "b.nl"])
    }
}
