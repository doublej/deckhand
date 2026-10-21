import Foundation

/// Why the Mac would not take a decision answer, in words a person can act on.
///
/// The daemon refuses with `{"detail": {"code": …, "error": …}}`; the code is what is read, and
/// the extras beside it (STALE's current hash, ANSWERED's answer) are left alone.
public enum DecisionRefusal: Error, Equatable, Sendable, LocalizedError {
    /// The page changed after this card was drawn — the question is not the one that was read.
    case stale
    case expired
    /// Somebody already answered it. First answer wins.
    case answered
    /// The phone holds the Mac's token rather than one of its own, so it has no key to answer with.
    case notPaired
    /// This phone already has another key on the Mac.
    case otherKey
    /// The Mac would not believe the proof: unsigned, a bad signature, a clock too far off, no key.
    case unproven(String)

    /// The refusal a decision answer's error stands for, or nil for any other failure.
    public init?(answering error: Error) {
        guard case DeckhandError.http(_, let body) = error,
              let refused = try? JSONDecoder().decode(Refused.self, from: Data(body.utf8)),
              case .string(let code)? = refused.detail["code"] else {
            return nil
        }
        switch code {
        case "STALE": self = .stale
        case "EXPIRED": self = .expired
        case "ANSWERED": self = .answered
        case "NO_KEY", "NOT_A_DEVICE": self = .notPaired
        case "KEY_TAKEN": self = .otherKey
        case "UNSIGNED", "BAD_SIGNATURE", "OLD_PROOF": self = .unproven(code)
        default: return nil
        }
    }

    /// FastAPI's `{"detail": {...}}` with the daemon's code in it. A detail that is a plain
    /// sentence fails to decode, which is a refusal this type does not stand for.
    private struct Refused: Decodable {
        let detail: [String: JSONValue]
    }

    public var errorDescription: String? {
        switch self {
        case .stale: "The question changed since this was shown — open it again"
        case .expired: "That decision has expired"
        case .answered: "That decision was already answered"
        case .notPaired: "Pair this phone by code to answer decisions"
        case .otherKey: "The Mac holds another key for this phone — re-pair it by code"
        case .unproven("OLD_PROOF"): "The phone's clock is too far from the Mac's"
        case .unproven(let code): "The Mac would not accept this phone's signature (\(code))"
        }
    }
}

public extension DeckhandClient {
    /// Hand the Mac this phone's public key. Needs a token of the phone's own (pair by code): the
    /// Mac's token is refused, because every agent can read it. The same key again is fine; a
    /// different one is refused until the phone is paired again.
    func registerKey(_ signer: any DecisionSigner) async throws {
        var req = request(.put, "devices/key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["publicKey": signer.registered])
        do {
            _ = try await send(req, body: body)
        } catch {
            throw DecisionRefusal(answering: error) ?? error
        }
    }

    /// Answer a decision: build the payload, sign its exact bytes, post the proof.
    ///
    /// `hash` is the page as the person saw it; the Mac refuses a proof for any other version.
    func answerDecision(
        _ artifact: String,
        in session: String,
        hash: String,
        value: JSONValue,
        signer: any DecisionSigner,
        now: Date = .now
    ) async throws -> Delivery {
        let payload = DecisionPayload(session: session, artifact: artifact, hash: hash,
                                      value: value, signedAt: now)
        let proof = try DecisionProof(payload, signedBy: signer)
        let path = "sessions/\(session)/artifacts/\(pathSafe(artifact))/answer"
        var req = request(.post, path)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["proof": proof])
        do {
            return try decode(try await send(req, body: body))
        } catch {
            throw DecisionRefusal(answering: error) ?? error
        }
    }

    /// Answer a notify with one of its action ids, signed as a decision of the session `notify`
    /// so the Mac checks it with the same key and the same rules. The Mac calls back once.
    func answerNotify(_ id: String, action: String, signer: any DecisionSigner, now: Date = .now)
        async throws {
        let payload = DecisionPayload(session: "notify", artifact: id, hash: "",
                                      value: .string(action), signedAt: now)
        var req = request(.post, "notify/\(pathSafe(id))/answer")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONEncoder().encode(["proof": try DecisionProof(payload, signedBy: signer)])
        do {
            _ = try await send(req, body: body)
        } catch {
            throw DecisionRefusal(answering: error) ?? error
        }
    }

    private func pathSafe(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }
}
