import Foundation
import Testing

@testable import DeckhandKit

/// The addresses the Mac found. An `extension ClientTests` for `ClientTests+Aliases.swift`'s reason.
extension ClientTests {
    @Test("an address arrives with its check and atlas's word, and missing keys are defaults")
    func decodesAddresses() async throws {
        StubProtocol.respond(with: Data(#"""
        {"addresses":[{"origin":"http://localhost:4109","kind":"ip","paths":[],"mentions":2,"said":true,
        "in_agents":true,"state":"loads","reach":"home","status":200,"title":"Eink","note":"",
        "lan_url":"http://192.168.1.2:4109/","tier":"important","why":"Staging","atlas":{"name":"eink","path":"/x","local":"https://e.nl","remote":""}},
        {"origin":"https://a.nl"}],"complete":false}
        """#.utf8))
        let listing = try await client().addresses(of: "s1")
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/s1/addresses")
        #expect(listing.complete == false)
        #expect(listing.addresses[0].inAgents && listing.addresses[0].lanUrl == "http://192.168.1.2:4109/")
        #expect(listing.addresses[0].atlas?.name == "eink")
        #expect(listing.addresses[1].state == "checking" && listing.addresses[1].atlas == nil)
        #expect(listing.addresses[0].tier == "important" && listing.addresses[0].why == "Staging")
        #expect(listing.addresses[1].tier == "recent")
    }
}
