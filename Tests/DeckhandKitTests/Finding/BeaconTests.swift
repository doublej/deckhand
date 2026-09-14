import Foundation
import Testing

@testable import DeckhandKit

/// Reading a TXT record, and the one rule that keeps a working pairing where it is. Both are
/// pure, so neither needs an `NWBrowser` — there is deliberately no test framework around one,
/// and none around `answering`, which is a `/health` call and not a decision.
@Suite("Beacons")
struct BeaconTests {
    @Test("the addresses come out of the TXT record, name first, in the order to try them")
    func reads() throws {
        let beacon = try #require(Beacon.read(
            name: "m2-2",
            txt: ["host": "m2-2.local:4180", "lan": "192.168.178.180:4180",
                  "name": "deckhand", "version": "0.1.0"]
        ))
        #expect(beacon.host == "m2-2.local:4180")
        #expect(beacon.lan == "192.168.178.180:4180")
        #expect(beacon.candidates == ["m2-2.local:4180", "192.168.178.180:4180"])
        #expect(beacon.name == "m2-2")
        #expect(beacon.version == "0.1.0")
        #expect(beacon.id == "m2-2.local:4180")
    }

    /// An older daemon says less, and a Mac that cannot work out its own IP says one address.
    /// Either is a beacon with one candidate rather than a row the phone drops.
    @Test("a record with only a name is still a Mac, with one address to try")
    func sparse() throws {
        let beacon = try #require(Beacon.read(name: "mini", txt: ["host": "mini.local"]))
        #expect(beacon.version == nil)
        #expect(beacon.lan == nil)
        #expect(beacon.candidates == ["mini.local"])
        // An empty version is the same absence spelled differently, and must not reach a label.
        #expect(Beacon.read(name: "mini", txt: ["host": "mini.local", "version": ""])?
            .version == nil)
    }

    /// The name is preferred, not required: a Mac whose `.local` name could not be worked out
    /// still has an address worth offering, and it is the one that ends up in the field.
    @Test("with no name the IP is promoted rather than the beacon being dropped")
    func promotes() throws {
        let beacon = try #require(Beacon.read(name: "mini", txt: ["lan": "10.0.0.4:4180"]))
        #expect(beacon.host == "10.0.0.4:4180")
        #expect(beacon.lan == nil)
        #expect(beacon.candidates == ["10.0.0.4:4180"])
    }

    /// Two tries and no more, so the same address twice would leave the fallback unused.
    @Test("a Mac that says the same address twice is tried once")
    func deduplicates() throws {
        let beacon = try #require(Beacon.read(
            name: "mini", txt: ["host": "10.0.0.4:4180", "lan": " 10.0.0.4:4180 "]
        ))
        #expect(beacon.lan == nil)
        #expect(beacon.candidates == ["10.0.0.4:4180"])
    }

    /// A row that fills the Address field with nothing is worse than no row: the person taps it,
    /// the field looks changed, and the app is further from working than before.
    @Test("a record with no usable address is not a Mac at all")
    func unusable() {
        #expect(Beacon.read(name: "m2-2", txt: [:]) == nil)
        #expect(Beacon.read(name: "m2-2", txt: ["host": "   ", "lan": ""]) == nil)
        #expect(Beacon.read(name: "m2-2", txt: ["name": "deckhand"]) == nil)
    }

    /// The name is the label and never the address, so a nameless registration falls back to
    /// the one thing it did say rather than drawing an empty row.
    @Test("a nameless beacon is labelled with its address")
    func nameless() throws {
        let beacon = try #require(Beacon.read(name: " ", txt: ["host": "10.0.0.4:4180"]))
        #expect(beacon.name == "10.0.0.4:4180")
    }

    /// Three openings and no more. The fourth case — a host that was typed and is answering —
    /// is the one this rule exists for.
    @Test("a working pairing is never moved, and an untouched one always is")
    func adoption() {
        #expect(ServerSettings.adopts("", answering: nil))
        #expect(ServerSettings.adopts("  ", answering: true))
        #expect(ServerSettings.adopts(ServerSettings.defaultHost, answering: true))
        #expect(ServerSettings.adopts("mini.local", answering: false))
        #expect(ServerSettings.adopts("mini.local", answering: true) == false)
    }

    /// Nil is "nobody has asked", which a check in flight and a missing token both are. Reading
    /// either of them as a failure would move an address the person typed by hand.
    @Test("an address nobody has tried yet is left alone")
    func unasked() {
        #expect(ServerSettings.adopts("mini.local", answering: nil) == false)
        #expect(ServerSettings.adopts("https://deckhand.jurrejan.com", answering: nil) == false)
    }

    /// Three states, three sentences. The screen reads this enum, so collapsing any two of them
    /// here is how "I could not ask" starts rendering as "there is none".
    @Test("looking, hearing nothing and being refused are three different answers")
    func distinct() {
        #expect(Looking.looking != Looking.nothing)
        #expect(Looking.refused != Looking.nothing)
        #expect(Looking.heard([]) != Looking.nothing)
        #expect(Looking.broken("dns") != Looking.refused)
    }
}
