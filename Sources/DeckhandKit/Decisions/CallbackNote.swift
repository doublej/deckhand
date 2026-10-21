import Foundation

/// A notify's notification (`POST /notify`): no session behind it, Allow and Deny on it, and a
/// caller on the Mac that the daemon answers once the tap is signed.
///
/// The notification carries only the notify's id and its words. Where the answer goes stays on
/// the Mac, so nothing a phone sends can redirect it. Pure, for `DecisionNote`'s reason.
public struct CallbackNote: Decodable, Equatable, Sendable {
    public let id: String
    public var question: String?

    /// The `notify` key out of a notification's `userInfo`, or nil for any other notification.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["notify"], JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let note = try? JSONDecoder().decode(CallbackNote.self, from: data) else { return nil }
        self = note
    }

    /// The one category the daemon maps an action set to; its ids are `approve` and `deny`.
    public enum Category {
        public static let allowDeny = "CALLBACK_ALLOW_DENY"
    }

    public enum Action {
        public static let approve = "CALLBACK_APPROVE"
        public static let deny = "CALLBACK_DENY"
    }

    /// The action id the Mac was given for this button, or nil for a tap that is not one.
    public static func action(for identifier: String) -> String? {
        switch identifier {
        case Action.approve: "approve"
        case Action.deny: "deny"
        default: nil
        }
    }
}
