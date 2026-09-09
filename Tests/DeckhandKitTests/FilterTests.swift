import Foundation
import Testing

@testable import DeckhandKit

/// The filters wire, decoded. No network in here: what is being tested is that a value the phone
/// has no type for goes out the way it came in, because the Mac reads its own settings back.
@Suite("Filters")
struct FilterTests {
    @Test("a settings value survives the trip whatever shape it is")
    func carriesEveryShape() throws {
        let values = try JSONDecoder().decode([String: JSONValue].self, from: Data("""
        {"text":"deckhand","whole":5,"fraction":2.5,"flag":true,"nothing":null,
         "pairs":[["deck hand","deckhand"]],"nested":{"lang":"nl"}}
        """.utf8))
        #expect(values["text"] == .string("deckhand"))
        #expect(values["whole"] == .int(5))
        #expect(values["fraction"] == .double(2.5))
        #expect(values["flag"] == .bool(true))
        #expect(values["nothing"] == .null)
        #expect(values["nested"] == .object(["lang": .string("nl")]))
        let again = try JSONDecoder().decode([String: JSONValue].self,
                                             from: try JSONEncoder().encode(values))
        #expect(again == values)
    }

    @Test("a whole number goes back whole, and true does not go back as 1")
    func keepsTheShapeOfANumber() throws {
        let written = try JSONEncoder().encode(["n": JSONValue.int(5), "b": .bool(true)])
        let text = try #require(String(bytes: written, encoding: .utf8))
        #expect(text.contains("\"n\":5"))
        #expect(!text.contains("5.0"))
        #expect(text.contains("\"b\":true"))
        // And the other way: what a number box hands back is whole when it reads whole, because
        // a ceiling of 5 written back as 5.0 is the Mac reading a different setting.
        #expect(JSONValue.number("5") == .int(5))
        #expect(JSONValue.number("2.5") == .double(2.5))
        #expect(JSONValue.number("") == .double(0))
    }

    @Test("a replacement list reads as rows of two, and only rows of two")
    func readsPairs() {
        let pairs = JSONValue.rows([["deck hand", "deckhand"], ["tu y", "TUI"]])
        #expect(pairs.rows == [["deck hand", "deckhand"], ["tu y", "TUI"]])
        // Half a row cannot be drawn and must not be written back as if it were whole.
        #expect(JSONValue.array([.array([.string("lonely")])]).rows.isEmpty)
        #expect(JSONValue.string("not a list").rows.isEmpty)
    }

    @Test("the Mac's description of its filters decodes, fields and all")
    func decodesWhatTheMacOffers() throws {
        let offered = try JSONDecoder().decode(FilterOffer.self, from: Data("""
        {"known":[{"name":"words","title":"Word replacement",
                   "summary":"Swaps words on the way in",
                   "fields":[{"key":"pairs","label":"Replacements","kind":"pairs",
                              "default":[["deck hand","deckhand"]],"hint":"One per row"},
                             {"key":"ceiling","label":"Words at most","kind":"number",
                              "default":40,"hint":""}]}],
         "steps":[{"filter":"words","on":true,"settings":{"max_words":12}}]}
        """.utf8))
        let filter = try #require(offered.known.first)
        #expect(filter.title == "Word replacement")
        #expect(filter.fields.map(\.kind) == [.pairs, .number])
        #expect(filter.fields.first?.defaultValue.rows == [["deck hand", "deckhand"]])
        #expect(filter.fields.last?.defaultValue == .int(40))
        let step = try #require(offered.steps.first)
        #expect(step.isOn)
        #expect(step.settings["max_words"] == .int(12))
    }

    @Test("a daemon that predates all of this costs nothing")
    func toleratesAnOlderMac() throws {
        let offered = try JSONDecoder().decode(FilterOffer.self, from: Data("{}".utf8))
        #expect(offered.known.isEmpty)
        #expect(offered.steps.isEmpty)
        // A step written down with no switch runs: being in the chain is the only reason for it
        // to have been written down.
        let step = try JSONDecoder().decode(FilterStep.self,
                                            from: Data("{\"filter\":\"words\"}".utf8))
        #expect(step.isOn)
        #expect(step.settings.isEmpty)
        // A kind this phone has never heard of is a text box rather than a failed screen, and a
        // field with no label is labelled with its own key rather than with nothing.
        let field = try JSONDecoder().decode(FilterField.self,
                                             from: Data("{\"key\":\"lang\",\"kind\":\"choice\"}".utf8))
        #expect(field.kind == .text)
        #expect(field.label == "lang")
    }

    @Test("the chain keeps its order, offers what is not in it, and drops nothing")
    func buildsTheChain() {
        let known = [Filter(name: "words", title: "Word replacement"),
                     Filter(name: "dutch", title: "Translate")]
        let chain = FilterStep.chain([FilterStep(filter: "gone"),
                                      FilterStep(filter: "dutch")], over: known)
        #expect(chain.map(\.filter) == ["gone", "dutch", "words"])
        // The one the Mac no longer offers is still there and still on; the one nobody has asked
        // for is appended off.
        #expect(chain.first?.isOn == true)
        #expect(chain.last?.isOn == false)
    }

    @Test("a receipt from a daemon that predates filtering has nothing to say and went")
    func toleratesAnOlderReceipt() throws {
        let receipt: UploadReceipt = try decoded("""
        {"path":"/tmp/x.m4a","bytes":13,"received_at":1.0,"transcript":"hello",
         "transcript_error":null,"delivered":true,"delivered_by":"keyboard","delivery_error":null}
        """)
        #expect(receipt.notes.isEmpty)
        #expect(receipt.stoppedBy == nil)
        #expect(receipt.went)
    }

    @Test("a filter's refusal is not a delivery, whatever else the Mac says")
    func readsARefusal() throws {
        let said: Delivery = try decoded("""
        {"delivered":true,"delivered_by":"keyboard","delivery_error":null,
         "notes":["swapped deck hand → deckhand"],"stopped_by":"guard"}
        """)
        // `delivered` is true in that payload. A stop is still a stop: the words did not go, and
        // a screen reading `delivered` alone would tell somebody their message was sent.
        #expect(!said.went)
        #expect(said.stoppedBy == "guard")
        #expect(said.notes == ["swapped deck hand → deckhand"])
    }

    /// The decoder the client uses for everything but filters, where `stopped_by` becomes
    /// `stoppedBy` on the way in.
    private func decoded<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}
