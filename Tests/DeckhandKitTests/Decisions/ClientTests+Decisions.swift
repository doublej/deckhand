import CryptoKit
import Foundation
import Testing

@testable import DeckhandKit

/// Decision answers on the wire. An `extension ClientTests` so it stays serialized with every
/// other suite that stubs the transport (`StubProtocol` is static).
extension ClientTests {
    @Test("a decision answer posts a proof the registered key verifies, and nothing else")
    func answersDecision() async throws {
        StubProtocol.respond(with: Data(#"{"delivered":true,"delivered_by":"keyboard"}"#.utf8))
        let signer = P256.Signing.PrivateKey()
        let sent = try await client().answerDecision(
            "tag-it", in: "sid", hash: "abc", value: .object(["answer": .bool(false)]),
            signer: signer, now: Date(timeIntervalSince1970: 100))
        #expect(sent.went)
        #expect(StubProtocol.lastRequest?.url?.path == "/sessions/sid/artifacts/tag-it/answer")
        let body = try #require(StubProtocol.lastBody)
        let wire = try JSONDecoder().decode([String: [String: String]].self, from: body)
        #expect(Array(wire.keys) == ["proof"])
        let proof = try #require(wire["proof"])
        let bytes = try #require(Data(base64Encoded: proof["payload"] ?? ""))
        #expect(String(bytes: bytes, encoding: .utf8) ==
            #"{"artifact":"tag-it","at":100,"hash":"abc","session":"sid","v":1,"value":{"answer":false}}"#)
        let signature = try P256.Signing.ECDSASignature(
            derRepresentation: try #require(Data(base64Encoded: proof["signature"] ?? "")))
        #expect(signer.publicKey.isValidSignature(signature, for: bytes))
    }

    @Test("a stale decision comes back as stale, not as a status")
    func staleDecision() async throws {
        StubProtocol.respond(with: Data(#"{"detail":{"code":"STALE","error":"x","hash":"new"}}"#.utf8),
                             status: 409)
        await #expect(throws: DecisionRefusal.stale) {
            try await client().answerDecision("tag-it", in: "sid", hash: "old",
                                              value: .object(["answer": .bool(true)]),
                                              signer: P256.Signing.PrivateKey())
        }
    }

    @Test("registering with the Mac's token says to pair by code")
    func registerWithMacToken() async throws {
        StubProtocol.respond(with: Data(#"{"detail":{"code":"NOT_A_DEVICE","error":"x"}}"#.utf8),
                             status: 403)
        let signer = P256.Signing.PrivateKey()
        await #expect(throws: DecisionRefusal.notPaired) { try await client().registerKey(signer) }
        #expect(StubProtocol.lastRequest?.httpMethod == "PUT")
        let body = try JSONDecoder().decode([String: String].self,
                                            from: try #require(StubProtocol.lastBody))
        #expect(body["publicKey"] == signer.publicKey.x963Representation.base64EncodedString())
    }
}
