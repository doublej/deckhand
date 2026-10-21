import CryptoKit
import DeckhandKit
import Foundation
import Security

/// The phone's decision key, in the Secure Enclave, and the one way an answer gets signed.
///
/// The private half never leaves the chip: what the keychain holds is the enclave's wrapped
/// `dataRepresentation`, which only this phone's enclave can use. Readable only while the phone is
/// unlocked, and never restored to another phone — a backup carries nothing that can sign. The
/// simulator has no enclave, so there it is a software key in the same keychain slot.
///
/// Compiled into the widget too (`project.yml`), for the `CardAction.swift` reason: the Lock
/// Screen's `AnswerSlip` names it, and the system performs that intent in the app's process — so
/// the default keychain group, which is the app's own, is where every signature is made.
struct EnclaveKeyStore: DecisionKeyStore {
    private static let service = "dev.jurrejan.deckhand.decision-key"

    func key() throws -> any DecisionSigner {
        if let kept = try read() { return try restored(kept) }
        let (signer, kept) = try made()
        try write(kept)
        return signer
    }

    private func restored(_ kept: Data) throws -> any DecisionSigner {
        SecureEnclave.isAvailable
            ? try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: kept)
            : try P256.Signing.PrivateKey(rawRepresentation: kept)
    }

    private func made() throws -> (any DecisionSigner, Data) {
        guard SecureEnclave.isAvailable else {
            let key = P256.Signing.PrivateKey()
            return (key, key.rawRepresentation)
        }
        var trouble: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, &trouble
        ) else {
            throw trouble.map { $0.takeRetainedValue() as Error } ?? KeyTrouble.keychain(errSecParam)
        }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        return (key, key.dataRepresentation)
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: "phone"]
    }

    private func read() throws -> Data? {
        var found: AnyObject?
        var ask = query
        ask[kSecReturnData as String] = true
        let status = SecItemCopyMatching(ask as CFDictionary, &found)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeyTrouble.keychain(status) }
        return found as? Data
    }

    private func write(_ kept: Data) throws {
        var item = query
        item[kSecValueData as String] = kept
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyTrouble.keychain(status) }
    }
}

extension SecureEnclave.P256.Signing.PrivateKey: @retroactive DecisionSigner {}

/// The keychain said no, which is a locked phone more often than anything else.
enum KeyTrouble: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(errSecInteractionNotAllowed): "Unlock the phone to answer"
        case .keychain(let status): "The phone's key could not be read (\(status))"
        }
    }
}

/// Sign and send one decision answer — the notification, the card, the tray and the slip's own
/// bar all come through here, so there is one way a person's tap becomes a proof.
enum PhoneKey {
    /// Registers the key first, every time. The same key again is a 200 and costs one round trip;
    /// in return there is no "is it registered" state on the phone to go stale against the Mac.
    static func answer(
        with client: DeckhandClient,
        artifact: String,
        in session: String,
        hash: String,
        value: JSONValue
    ) async throws -> Delivery {
        let signer = try EnclaveKeyStore().key()
        try await client.registerKey(signer)
        return try await client.answerDecision(artifact, in: session, hash: hash, value: value,
                                               signer: signer)
    }

    /// A notify's Allow or Deny, signed the same way and registered first for the same reason.
    static func answerNotify(with client: DeckhandClient, id: String, action: String) async throws {
        let signer = try EnclaveKeyStore().key()
        try await client.registerKey(signer)
        try await client.answerNotify(id, action: action, signer: signer)
    }

    /// Hand the Mac the key now — after pairing by code, so a refusal is heard there and not at
    /// the first decision.
    static func register(with client: DeckhandClient) async throws {
        try await client.registerKey(try EnclaveKeyStore().key())
    }
}
