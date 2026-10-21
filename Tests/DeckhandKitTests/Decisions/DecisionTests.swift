import CryptoKit
import Foundation
import Testing

@testable import DeckhandKit

@Suite("Decisions")
struct DecisionTests {
    private let payload = DecisionPayload(
        session: "sid", artifact: "tag-it", hash: "abc123",
        value: .object(["answer": .bool(true)]), signedAt: Date(timeIntervalSince1970: 1_761_148_800.9)
    )

    @Test("the payload is one spelling: sorted keys, whole seconds, slashes left alone")
    func payloadBytes() throws {
        let slashed = DecisionPayload(session: "s", artifact: "a", hash: "h",
                                      value: .object(["answer": .string("a/b")]),
                                      signedAt: Date(timeIntervalSince1970: 5))
        #expect(String(bytes: try payload.encoded(), encoding: .utf8) ==
            #"{"artifact":"tag-it","at":1761148800,"hash":"abc123","session":"sid","v":1,"value":{"answer":true}}"#)
        #expect(String(bytes: try slashed.encoded(), encoding: .utf8) ==
            #"{"artifact":"a","at":5,"hash":"h","session":"s","v":1,"value":{"answer":"a/b"}}"#)
    }

    /// The formats the daemon verifies with, pinned on this side: the key as base64 x963, the
    /// payload as base64 bytes, the signature as base64 DER over exactly those bytes.
    @Test("a proof verifies with the registered key, read back the way the daemon reads it")
    func proofRoundTrips() throws {
        let signer = try SoftwareKeyStore().key()
        let proof = try DecisionProof(payload, signedBy: signer)
        let keyBytes = try #require(Data(base64Encoded: signer.registered))
        #expect(keyBytes.count == 65)
        let key = try P256.Signing.PublicKey(x963Representation: keyBytes)
        let bytes = try #require(Data(base64Encoded: proof.payload))
        let signature = try P256.Signing.ECDSASignature(
            derRepresentation: try #require(Data(base64Encoded: proof.signature)))
        #expect(key.isValidSignature(signature, for: bytes))
        #expect(bytes == (try payload.encoded()))
        #expect(!key.isValidSignature(signature, for: Data(bytes.dropLast())))
    }

    @Test("the store hands back the same key every time")
    func storeKeepsItsKey() throws {
        let store = SoftwareKeyStore()
        #expect(try store.key().registered == (try store.key().registered))
    }

    /// The daemon's own vector, when this checkout has it: `daemon/tests/decisions/vector.json`.
    @Test("the daemon's vector verifies here", .enabled(if: DecisionTests.vector != nil))
    func daemonVector() throws {
        let vector = try #require(Self.vector)
        let key = try P256.Signing.PublicKey(
            x963Representation: try #require(Data(base64Encoded: vector["publicKey"] ?? "")))
        let signature = try P256.Signing.ECDSASignature(
            derRepresentation: try #require(Data(base64Encoded: vector["signature"] ?? "")))
        let bytes = try #require(Data(base64Encoded: vector["payload"] ?? ""))
        #expect(key.isValidSignature(signature, for: bytes))
    }

    static var vector: [String: String]? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appending(path: "daemon/tests/decisions/vector.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    @Test("each button answers in the shape the slip's own page sends")
    func notificationValues() {
        typealias Note = DecisionNote
        let confirm = Note.Category.confirm
        #expect(Note.value(category: confirm, action: Note.Action.approve, typed: nil)
            == .object(["answer": .bool(true)]))
        #expect(Note.value(category: confirm, action: Note.Action.deny, typed: nil)
            == .object(["answer": .bool(false)]))
        #expect(Note.value(category: confirm, action: Note.Action.reply, typed: " later ")
            == .object(["reply": .string("later")]))
        #expect(Note.value(category: Note.Category.text, action: Note.Action.reply, typed: "v2")
            == .object(["answer": .string("v2")]))
        #expect(Note.value(category: confirm, action: Note.Action.reply, typed: "  ") == nil)
        #expect(Note.value(category: Note.Category.pick, action: Note.Action.approve, typed: nil) == nil)
        #expect(Note.value(category: confirm, action: "com.apple.UNNotificationDefaultActionIdentifier",
                           typed: nil) == nil)
    }

    @Test("a notification's decision key is read out of userInfo, and nothing else is one")
    func readsNote() throws {
        let info: [AnyHashable: Any] = [
            "aps": ["category": "DECISION_CONFIRM"],
            "decision": ["session": "sid", "artifact": "tag-it", "hash": "abc", "kind": "confirm",
                         "choices": ["Tag", "Not yet"], "question": "Tag v1?"]
        ]
        let note = try #require(DecisionNote(userInfo: info))
        #expect(note.session == "sid")
        #expect(note.hash == "abc")
        #expect(note.choices == ["Tag", "Not yet"])
        #expect(DecisionNote(userInfo: ["deckhand": "manager"]) == nil)
    }

    @Test("a notify's buttons send the Mac's own action ids, and only its own key decodes")
    func callbackNotes() throws {
        #expect(CallbackNote.action(for: CallbackNote.Action.approve) == "approve")
        #expect(CallbackNote.action(for: CallbackNote.Action.deny) == "deny")
        #expect(CallbackNote.action(for: "com.apple.UNNotificationDefaultActionIdentifier") == nil)
        let note = try #require(CallbackNote(userInfo: ["notify": ["id": "ab12", "question": "In?"]]))
        #expect(note.id == "ab12")
        #expect(note.question == "In?")
        #expect(CallbackNote(userInfo: ["decision": ["session": "sid"]]) == nil)
    }

    @Test("a refusal's code becomes a sentence, and anything else stays the error it was")
    func refusals() {
        func refusal(_ status: Int, _ code: String) -> DecisionRefusal? {
            DecisionRefusal(answering: DeckhandError.http(
                status, #"{"detail":{"code":"\#(code)","error":"x","answer":{"answer":"STALE"}}}"#))
        }
        #expect(refusal(409, "ANSWERED") == .answered)
        #expect(refusal(409, "STALE") == .stale)
        #expect(refusal(410, "EXPIRED") == .expired)
        #expect(refusal(403, "NOT_A_DEVICE") == .notPaired)
        #expect(refusal(403, "NO_KEY") == .notPaired)
        #expect(refusal(409, "KEY_TAKEN") == .otherKey)
        #expect(refusal(403, "BAD_SIGNATURE") == .unproven("BAD_SIGNATURE"))
        #expect(refusal(400, "MISMATCH") == nil)
        #expect(DecisionRefusal(answering: DeckhandError.http(500, #"{"detail":"boom"}"#)) == nil)
        #expect(DecisionRefusal(answering: DeckhandError.notLive) == nil)
        #expect(DecisionRefusal.notPaired.errorDescription == "Pair this phone by code to answer decisions")
    }

    @Test("a decision row becomes the controls its page would have drawn")
    func decisionControls() {
        func row(_ kind: String?, _ choices: [String]) -> SlipAsk? {
            Artifact(id: "a", title: "A", modified: 1, answered: false, decision: kind,
                     choices: choices, hash: "h").decisionAsk
        }
        #expect(row("confirm", ["Tag", "Not yet"])
            == SlipAsk(kind: .confirm, accept: "Tag", decline: "Not yet"))
        #expect(row("pick", ["main", "dev"]) == SlipAsk(kind: .pick, options: ["main", "dev"], other: true))
        #expect(row("text", ["Name"]) == SlipAsk(kind: .text, label: "Name"))
        #expect(row(nil, []) == nil)
    }

    @Test("a decision page's respond throws; any other page's does not")
    func bridgeRefusesDecisions() {
        let decision = Artifact(id: "tag-it", title: "Tag?", modified: 1, answered: false,
                                decision: "confirm", hash: "abc")
        let note = Artifact(id: "note", title: "Note", modified: 1, answered: false)
        #expect(ArtifactPage.bridge(for: decision).contains("if (true) throw new Error("))
        #expect(ArtifactPage.bridge(for: note).contains("if (false) throw new Error("))
    }

    @Test("a listing row carries a decision's fields, and an older row reads as no decision")
    func decodesDecisionRow() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let row = try decoder.decode(Artifact.self, from: Data("""
        {"id":"tag-it","title":"Tag?","modified":1.0,"answered":true,"decision":"confirm",
         "choices":["Tag","Not yet"],"action":"Tags v1","expires":1761148800,"hash":"abc",
         "verified":true,"answered_by":"JJ's iPhone","expired":false}
        """.utf8))
        #expect(row.isDecision)
        #expect(row.choices == ["Tag", "Not yet"])
        #expect(row.answeredBy == "JJ's iPhone")
        let old = try decoder.decode(Artifact.self, from: Data("""
        {"id":"a","title":"A","modified":1.0,"answered":false}
        """.utf8))
        #expect(!old.isDecision)
        #expect(old.hash == nil)
    }
}
