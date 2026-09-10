import Foundation
import Testing

@testable import DeckhandKit

/// What a session has been told to keep in mind.
///
/// An `extension ClientTests` in the `Wire` folder rather than a suite of its own, for the reason
/// `ClientTests+Turns.swift` gives at the top of it: `StubProtocol` is static, so a second suite
/// stubbing the same transport answers the first one's requests.
extension ClientTests {
    @Test("orders come back with the cap the Mac will actually clamp at")
    func decodesOrders() async throws {
        StubProtocol.respond(with: Data(#"{"text":"always run just check","limit":2000}"#.utf8))
        let orders = try await client().orders(of: "s")
        #expect(orders.text == "always run just check")
        #expect(orders.limit == 2000)
        #expect(orders.inForce)
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/s/orders")
    }

    /// A session that has never been given any, which is most of them. Nothing on screen may read
    /// this as orders in force, because the Mac adds nothing at all to a prompt for such a session.
    @Test("a session with no orders is not running under any")
    func decodesEmptyOrders() async throws {
        StubProtocol.respond(with: Data(#"{"text":"","limit":2000}"#.utf8))
        #expect(try await client().orders(of: "s").inForce == false)
        StubProtocol.respond(with: Data(#"{"text":"  \n  ","limit":2000}"#.utf8))
        #expect(try await client().orders(of: "s").inForce == false)
    }

    /// The cap is the Mac's to send and the phone's to draw, never the phone's to assume: a daemon
    /// that stops sending it costs the pane its counter and nothing else.
    @Test("orders decode from a daemon that names no cap")
    func decodesOrdersWithoutALimit() async throws {
        StubProtocol.respond(with: Data(#"{"text":"ship nothing on a Friday"}"#.utf8))
        let orders = try await client().orders(of: "s")
        #expect(orders.limit == nil)
        #expect(orders.inForce)
    }

    /// What comes back is what was *stored*, which is not what was sent: the Mac strips anything a
    /// terminal would act on and clamps what is too long.
    @Test("saving orders sends the words and takes back what the Mac kept")
    func savesOrders() async throws {
        StubProtocol.respond(with: Data(#"{"text":"keep it short","limit":2000}"#.utf8))
        let saved = try await client().saveOrders("keep it short\u{1b}[31m", of: "s")
        #expect(saved.text == "keep it short")
        #expect(StubProtocol.lastRequest?.httpMethod == "PUT")
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/s/orders")
    }
}
