import Foundation

/// Every place in the app a `deckhand://` URL can open, read off the URL once.
///
/// The shapes follow the app as it is laid out, not as a list of screens:
///
/// | URL | Opens |
/// |---|---|
/// | `deckhand://sessions` | the sessions list, with nothing pushed over it |
/// | `deckhand://sessions/<id or name>` | that session's page, on its transcript |
/// | `deckhand://sessions/<id>/<pane>` | `transcript`, `summary` or `dashboard` |
/// | `deckhand://sessions/<id>/<square>` | the dashboard with that square's sheet up: `slips`, `files`, `orders`, `agents`, `filters`, `context`, `project`, `commands`, `addresses` |
/// | `deckhand://sessions/<id>/slips/<slip id>` | that one slip, full screen |
/// | `deckhand://manager` | the manager's drawer, on its conversation |
/// | `deckhand://manager?say=<words>` | the same, with the words in the field — **never sent** |
/// | `deckhand://tray` | the drawer, on the tray |
/// | `deckhand://projects`, `deckhand://settings` | the project picker, settings |
///
/// `deckhand://sessions/<id>` is `CardLink`'s shape, so every Lock Screen card already speaks
/// this. A notification carries one as `link` in its payload.
///
/// **`say` fills the field and stops.** A link can come from anywhere — a slip, a web page, a
/// message — and words sent to the manager are the person speaking. Sending them on open would
/// make every link a way to speak as the person; laying them in the field leaves the press theirs.
///
/// The pane is carried as the words in the URL, not as an enum: the session page already answers
/// to exactly these names from the manager (`SessionView.show`), and a second list of them here
/// would be a second place for them to drift apart.
public enum DeepLink: Equatable, Sendable {
    case sessions
    case session(String, pane: String?)
    case manager(say: String?)
    case tray
    case projects
    case settings

    public init?(_ url: URL) {
        guard url.scheme == CardLink.scheme else { return nil }
        // `pathComponents` leads with "/" and hands back what the escaping put in.
        let path = Array(url.pathComponents.dropFirst())
        switch url.host() {
        case "sessions":
            guard let wanted = path.first, !wanted.isEmpty else {
                self = .sessions
                return
            }
            let pane = path.dropFirst().joined(separator: "/")
            self = .session(wanted, pane: pane.isEmpty ? nil : pane)
        case "manager":
            let said = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "say" }?.value
            self = .manager(say: said?.isEmpty == false ? said : nil)
        case "tray": self = .tray
        case "projects": self = .projects
        case "settings": self = .settings
        default: return nil
        }
    }
}
