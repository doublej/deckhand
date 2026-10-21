import CryptoKit
import Foundation

/// What proves the person tapped: the phone's own key, signing exactly what was answered.
///
/// The Mac's token is a file every agent on the Mac can read, so it cannot tell the phone from an
/// agent. A P-256 key that lives on the phone can — the daemon holds its public half (registered
/// once, with a token of this phone's own) and refuses a decision answer that it did not sign. The
/// signature covers the session, the page, the page's hash, the value and the moment, so it
/// answers one version of one question once and cannot be replayed onto another.
///
/// The key is a protocol so the Secure Enclave one can live app-side, where the hardware is, and
/// everything else here can run under `just test` with a software key.
public protocol DecisionSigner {
    var publicKey: P256.Signing.PublicKey { get }
    func signature<D: DataProtocol>(for data: D) throws -> P256.Signing.ECDSASignature
}

extension P256.Signing.PrivateKey: DecisionSigner {}

/// Where the phone's key is kept: made the first time it is asked for, the same key after that.
public protocol DecisionKeyStore {
    func key() throws -> any DecisionSigner
}

/// A key in memory and nowhere else — the store `just test` and a Mac use. The app's own is the
/// Secure Enclave (`deckhand/Decisions/PhoneKey.swift`).
public final class SoftwareKeyStore: DecisionKeyStore {
    private let made: P256.Signing.PrivateKey

    public init(_ key: P256.Signing.PrivateKey = P256.Signing.PrivateKey()) { made = key }

    public func key() throws -> any DecisionSigner { made }
}

/// What is signed, in the daemon's words: `{"v":1,"session","artifact","hash","value","at"}`.
///
/// `at` is whole Unix seconds. The daemon refuses a proof more than five minutes off its clock.
public struct DecisionPayload: Encodable, Equatable, Sendable {
    public let version: Int
    public let session: String
    public let artifact: String
    public let hash: String
    public let value: JSONValue
    public let signedAt: Int

    enum CodingKeys: String, CodingKey {
        case version = "v", session, artifact, hash, value, signedAt = "at"
    }

    public init(session: String, artifact: String, hash: String, value: JSONValue, signedAt: Date) {
        version = 1
        self.session = session
        self.artifact = artifact
        self.hash = hash
        self.value = value
        self.signedAt = Int(signedAt.timeIntervalSince1970)
    }

    /// The exact bytes that are signed and sent. Sorted keys, slashes as they are: one spelling,
    /// so the bytes the phone signed are the bytes the daemon checks.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// The body of a decision answer: the payload and its DER signature, both base64.
public struct DecisionProof: Encodable, Equatable, Sendable {
    public let payload: String
    public let signature: String

    public init(_ payload: DecisionPayload, signedBy signer: any DecisionSigner) throws {
        let bytes = try payload.encoded()
        self.payload = bytes.base64EncodedString()
        signature = try signer.signature(for: bytes).derRepresentation.base64EncodedString()
    }
}

public extension DecisionSigner {
    /// The public half as the daemon stores it: base64 of the 65-byte uncompressed point.
    var registered: String { publicKey.x963Representation.base64EncodedString() }
}
