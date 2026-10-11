import Foundation
import Testing

@testable import DeckhandKit

/// Where the person is. An `extension ClientTests` for the reason `ClientTests+Turns.swift` gives:
/// `StubProtocol` is static, and a second suite would answer the first one's requests.
extension ClientTests {
    /// The polls alone cannot say the phone is in a hand, so a touch says it outright.
    @Test("a touch on the phone is said to the Mac as a POST to presence/phone")
    func marksPhoneInUse() async throws {
        StubProtocol.respond(with: Data())
        try await client().markPhoneInUse()
        #expect(StubProtocol.lastRequest?.httpMethod == "POST")
        #expect(StubProtocol.lastRequest?.url?.path == "/presence/phone")
    }
}
