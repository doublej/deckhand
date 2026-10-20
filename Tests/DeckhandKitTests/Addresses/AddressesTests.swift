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

    @Test("rows are grouped by where they open from, and an empty heading is not drawn")
    func groupsByReach() {
        let rows = [Address(origin: "https://a.nl"), Address(origin: "http://localhost:1", reach: "mac")]
        #expect(Addresses.sections(rows).map(\.title) == ["Only on the Mac", "Internet"])
    }

    @Test("the square counts what answers, and says so in words when there is nothing")
    func countsWhatAnswers() {
        #expect(Addresses.count(nil) == "…")
        #expect(Addresses.count([]) == "None yet")
        let rows = [Address(origin: "https://www.a.nl", state: "down"), Address(origin: "https://b.nl")]
        #expect(Addresses.count(rows) == "1 live")
        #expect(Addresses.worth(rows) == ["b.nl", "a.nl"])
    }
}
