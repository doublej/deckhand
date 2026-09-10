import Foundation
import Testing

@testable import DeckhandKit

/// The merge and the wire, which are the two places a millisecond can go wrong without anybody
/// noticing: a stage counted twice reads as a slow Mac, and a stage dropped reads as a fast one.
@Suite("What a clip cost")
struct ClipTimingTests {
    private func makeSpans() -> PhoneSpans {
        var spans = PhoneSpans()
        spans.arming = 40
        spans.spoken = 4200
        spans.finishing = 12
        spans.keeping = 8
        spans.upload = 2000
        return spans
    }

    private let mac = [Stage(name: "session", took: 500),
                       Stage(name: "utt", took: 1200),
                       Stage(name: "total", took: 1700)]

    @Test("The network is what the upload cost minus what the Mac spent inside it")
    func networkIsDerived() {
        let timing = ClipTiming.merged(phone: makeSpans(), mac: mac, macTotal: 1700)

        #expect(timing.stages.first { $0.name == "network" }?.took == 300)
        // The Mac's own total is not a stage: it is the sum of its stages and would be counted
        // twice, which is the one arithmetic mistake this whole breakdown could make.
        #expect(!timing.stages.contains { $0.name == "total" })
        #expect(timing.total == 40 + 12 + 8 + 300 + 500 + 1200)
    }

    @Test("Talking is measured and deliberately left out of the total")
    func spokenIsNotACost() {
        let timing = ClipTiming.merged(phone: makeSpans(), mac: mac, macTotal: 1700)

        #expect(timing.spoken == 4200)
        #expect(timing.total < timing.spoken)
    }

    @Test("A Mac that reports nothing still gives an honest breakdown")
    func anOlderMacStillAdds() {
        let timing = ClipTiming.merged(phone: makeSpans(), mac: [], macTotal: nil)

        // With nothing to subtract, the round trip cannot be told from the work done inside it,
        // so it is called nothing rather than called network. The phone's own spans still stand.
        #expect(timing.stages.first { $0.name == "network" }?.took == 0)
        #expect(timing.total == 60)
    }

    @Test("Two clocks disagreeing never prints a negative span")
    func neverNegative() {
        var spans = makeSpans()
        spans.upload = 1500
        let timing = ClipTiming.merged(phone: spans, mac: mac, macTotal: 1700)

        #expect(timing.stages.first { $0.name == "network" }?.took == 0)
    }

    @Test("The card appearing is written once, however often the card comes back")
    func showingIsReplaced() {
        var timing = ClipTiming.merged(phone: makeSpans(), mac: mac, macTotal: 1700)
        timing.showed(9)
        timing.showed(400)

        #expect(timing.stages.filter { $0.name == "showing" }.count == 1)
        #expect(timing.stages.last?.took == 400)
    }

    // MARK: - the wire

    @Test("The Mac's stages arrive in the order they ran, with their names intact")
    func stagesDecodeInOrder() throws {
        let receipt: UploadReceipt = try decoded("""
        {"path":"/tmp/x.m4a","bytes":64,"received_at":1.0,"transcript":"go on",
         "delivered":true,"delivered_by":"keyboard",
         "timings":[{"name":"session","ms":512.3},{"name":"utt","ms":1840.0},
                    {"name":"total","ms":2400.1}]}
        """)

        #expect(receipt.timings.map(\.name) == ["session", "utt", "total"])
        #expect(receipt.macTotal == 2400.1)
    }

    @Test("A Mac that measures nothing is not an error, it is an empty list")
    func anOlderMacSaysNothing() throws {
        let receipt: UploadReceipt = try decoded("""
        {"path":"/tmp/x.m4a","bytes":64,"received_at":1.0,"transcript":"go on","delivered":true}
        """)

        #expect(receipt.timings.isEmpty)
        #expect(receipt.macTotal == nil)
        #expect(!receipt.uttRewrote)
    }

    @Test("utt's own rewrite is read off its stages, never off raw against text")
    func uttRewroteAsksTheStages() throws {
        // None of this exists on utt's jobs lane today; the daemon passes through whatever it
        // sends, and this is the shape it will send when it sends anything.
        let trimmed: UploadReceipt = try decoded("""
        {"path":"/tmp/x.m4a","bytes":64,"received_at":1.0,"transcript":"ship it",
         "raw":"ship it ","stages":[],"delivered":true}
        """)
        // `raw` differs, and only by whitespace. utt's own `ProcessedTranscript.changed` uses
        // `stages` for exactly this reason, and so does this.
        #expect(trimmed.raw == "ship it ")
        #expect(!trimmed.uttRewrote)

        let rewritten: UploadReceipt = try decoded("""
        {"path":"/tmp/x.m4a","bytes":64,"received_at":1.0,"transcript":"ship it",
         "raw":"ship it, actually ship it","stages":["cleanup"],
         "cleanupSkipped":null,"delivered":true}
        """)
        #expect(rewritten.uttRewrote)
        #expect(rewritten.uttStages == ["cleanup"])
        // And utt's `stages` does not land on the daemon's own `timings`, which is the whole
        // reason one of these two keys is spelled out in `CodingKeys`.
        #expect(rewritten.timings.isEmpty)
    }

    @Test("The slowest stage is the one worth naming first")
    func slowestIsFound() {
        let timing = ClipTiming.merged(phone: makeSpans(), mac: mac, macTotal: 1700)

        #expect(timing.slowest?.name == "utt")
        #expect(timing.slowest?.title == "utt transcribed")
        // The one stage that needs a sentence under it, because up to 300 ms of it is utt not
        // having looked at the folder yet rather than utt working.
        #expect(timing.slowest?.note != nil)
        #expect(Stage(name: "utt", took: 1).side == .mac)
        #expect(Stage(name: "keeping", took: 1).side == .phone)
        #expect(Stage(name: "network", took: 1).side == .wire)
    }

    private func decoded<T: Decodable>(_ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }
}
