import Foundation

/// The sessions a manager reply names, made into links.
///
/// The manager writes a session's name in bold or as code — `**rusty-auk**`, `` `deckhand` `` —
/// and when its prompt asked it to write links instead, it went on writing bold. So the link is
/// put in here, where it cannot be forgotten: a name in either form that is a live session becomes
/// `CardLink`'s `deckhand://sessions/<id>`, which the Mac follows to that session's iTerm window
/// and tab. Plain words are left alone — `deckhand` the product is not `deckhand` the session.
public enum ManagerLinks {
    /// `sessions` maps a name to its session id.
    public static func linked(_ text: String, sessions: [String: String]) -> String {
        sessions.reduce(text) { text, session in
            guard let url = CardLink.toSession(session.value)?.absoluteString else { return text }
            let name = session.key
            return text
                .replacingOccurrences(of: "**\(name)**", with: "**[\(name)](\(url))**")
                .replacingOccurrences(of: "`\(name)`", with: "[\(name)](\(url))")
        }
    }
}
