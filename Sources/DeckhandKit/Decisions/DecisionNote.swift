import Foundation

/// A decision's notification, as the daemon sends it, and what each of its buttons answers.
///
/// The words are the daemon's: `aps.category` is one of the three `Category` values and the
/// custom key `decision` carries what the phone signs. Pure, so `just test` holds down the one
/// mapping that matters most here — which button sends which value.
public struct DecisionNote: Decodable, Equatable, Sendable {
    public let session: String
    public let artifact: String
    public let hash: String
    public let kind: String
    public var choices: [String]?
    public var question: String?

    /// The `decision` key out of a notification's `userInfo`, or nil for any other notification.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["decision"], JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let note = try? JSONDecoder().decode(DecisionNote.self, from: data) else { return nil }
        self = note
    }

    /// The notification categories, one per kind of decision.
    public enum Category {
        public static let confirm = "DECISION_CONFIRM"
        public static let pick = "DECISION_PICK"
        public static let text = "DECISION_TEXT"
    }

    /// The buttons on them.
    public enum Action {
        public static let approve = "DECISION_APPROVE"
        public static let deny = "DECISION_DENY"
        public static let reply = "DECISION_REPLY"
    }

    /// What a button answers, in the shape the slip's own page sends: a confirm is
    /// `{"answer": bool}` and a text is `{"answer": words}`. A confirm's Reply is new —
    /// `{"reply": words}` — because words are not a yes or a no. Nil for anything that is not an
    /// answer: a tap on the body, a dismissal, a Reply with nothing typed.
    public static func value(category: String, action: String, typed: String?) -> JSONValue? {
        let words = typed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (category, action) {
        case (Category.confirm, Action.approve): return .object(["answer": .bool(true)])
        case (Category.confirm, Action.deny): return .object(["answer": .bool(false)])
        case (Category.confirm, Action.reply) where !words.isEmpty:
            return .object(["reply": .string(words)])
        case (Category.text, Action.reply) where !words.isEmpty:
            return .object(["answer": .string(words)])
        default: return nil
        }
    }
}

public extension Artifact {
    /// A decision as the app's own controls ask it — the bar under its page. Its choices are the
    /// page's own words; a pick also takes an answer typed in, as the page's last row does. Nil
    /// for a slip that is not a decision.
    var decisionAsk: SlipAsk? {
        let words = choices ?? []
        switch decision {
        case "confirm":
            return SlipAsk(kind: .confirm, accept: words.first, decline: words.dropFirst().first)
        case "pick": return SlipAsk(kind: .pick, options: words, other: true)
        case "text": return SlipAsk(kind: .text, label: words.first)
        default: return nil
        }
    }
}
