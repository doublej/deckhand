import Foundation

/// What the Mac wrote to disk for an uploaded clip. `transcript` stays nil until phase two.
public struct UploadReceipt: Codable, Hashable, Sendable {
    public let path: String
    public let bytes: Int
    public let receivedAt: Double
    public let transcript: String?
    public let transcriptError: String?
    /// The words after the chain has run over them, and nil when it changed nothing. Only on a
    /// clip that asked not to be delivered — there is nothing to prepare for words already gone.
    public var prepared: String?
    /// Whether the text reached the session itself, which way it went in, and why not when
    /// it did not.
    public let delivered: Bool
    public let deliveredBy: String?
    public let deliveryError: String?
    /// The filters' own two answers, exactly as on `Delivery`: what they wanted to say, and
    /// which of them refused. Both absent from a daemon that predates filtering.
    public var notes: [String] = []
    public var stoppedBy: String?
    /// What each stage on the Mac cost, in milliseconds and in the order they ran. Empty from a
    /// daemon that predates the measurement, which is the only state this has to tolerate.
    public var timings: [Stage] = []
    /// The recogniser's own words, before utt's own pipeline touched them.
    ///
    /// **This does not exist yet.** utt's jobs lane answers with `text`, `error` and
    /// `finishedAt`; `raw` is in scope in its `ProcessedTranscript` and dropped at that
    /// boundary. Nothing here stubs it: the daemon passes through whatever utt sends, and the
    /// day utt sends this the card starts showing what its cleanup rewrote. Until then it is
    /// nil and nothing appears.
    public var raw: String?
    /// The utt stages that actually *changed* the words — not the ones that ran.
    ///
    /// It is this and not `raw != text` that says a rewrite happened, exactly as utt's own
    /// `ProcessedTranscript.changed` does: the pipeline trims, and whitespace is not something
    /// to show a person a before-and-after of.
    public var uttStages: [String] = []
    /// Set when utt's cleanup was on and did not run, with the reason it gives.
    public var cleanupSkipped: String?

    public var went: Bool { delivered && stoppedBy == nil }

    /// What the Mac said the whole request took. The upload span with this taken out of it is
    /// the network, which is why nothing measures the network twice.
    public var macTotal: Double? { timings.first { $0.name == "total" }?.took }

    /// True when utt's own pipeline rewrote the words on the way here, and there is therefore a
    /// before and an after worth showing. False on every Mac until utt starts sending `raw`.
    public var uttRewrote: Bool { raw != nil && !uttStages.isEmpty }

    /// The words to put in front of the person: what the chain made of them, or what utt heard
    /// when the chain left them alone.
    ///
    /// `transcript` keeps meaning what was heard, which is why this is a second field and not a
    /// rewrite of the first. The card has to show this one: a card reading "deck hand" while the
    /// session is about to be handed "deckhand" lies about the very thing it exists to confirm.
    public var words: String? { prepared ?? transcript }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        path = try box.decodeIfPresent(String.self, forKey: .path) ?? ""
        bytes = try box.decodeIfPresent(Int.self, forKey: .bytes) ?? 0
        receivedAt = try box.decodeIfPresent(Double.self, forKey: .receivedAt) ?? 0
        transcript = try box.decodeIfPresent(String.self, forKey: .transcript)
        transcriptError = try box.decodeIfPresent(String.self, forKey: .transcriptError)
        prepared = try box.decodeIfPresent(String.self, forKey: .prepared)
        delivered = try box.decodeIfPresent(Bool.self, forKey: .delivered) ?? false
        deliveredBy = try box.decodeIfPresent(String.self, forKey: .deliveredBy)
        deliveryError = try box.decodeIfPresent(String.self, forKey: .deliveryError)
        notes = try box.decodeIfPresent([String].self, forKey: .notes) ?? []
        stoppedBy = try box.decodeIfPresent(String.self, forKey: .stoppedBy)
        timings = try box.decodeIfPresent([Stage].self, forKey: .timings) ?? []
        raw = try box.decodeIfPresent(String.self, forKey: .raw)
        uttStages = try box.decodeIfPresent([String].self, forKey: .uttStages) ?? []
        cleanupSkipped = try box.decodeIfPresent(String.self, forKey: .cleanupSkipped)
    }

    /// Spelled out because one key has to be: utt writes `stages`, and this type already has
    /// stages of its own under `timings`. The rest are the synthesised names — `.convertFromSnakeCase`
    /// has already turned `transcript_error` into `transcriptError` before any of them is looked up.
    enum CodingKeys: String, CodingKey {
        case path, bytes, receivedAt, transcript, transcriptError, prepared
        case delivered, deliveredBy, deliveryError, notes, stoppedBy
        case timings, raw, cleanupSkipped
        case uttStages = "stages"
    }
}
