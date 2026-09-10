import Foundation

/// The things you do *to* a session rather than say to it. Each is a keystroke in its pane on
/// the Mac, exactly as it would be typed by hand.
///
/// The raw values are the wire words `deliver.CONTROLS` is keyed by on the Mac, and nothing joins
/// the two lists but the spelling — `ControlTests.wire` and the daemon's own
/// `test_every_control_the_phone_offers_is_one_the_daemon_knows` are the join, one from each end.
///
/// Split out of `Models.swift` when `exit` pushed that file past 300 lines. It earns a file: two
/// of these cannot be undone, and what the phone says before doing one is here with the control
/// rather than in the sheet that shows it.
public enum Control: String, CaseIterable, Sendable {
    /// Escape: stop what it is doing now.
    case cancel
    /// `/compact`: fold the conversation so far into a summary and carry on.
    case compact
    /// `/clear`: throw the conversation away. There is no undo, so the phone asks first.
    case clear
    /// `/exit`: quit Claude Code. The session is gone from the rail the moment its process is,
    /// and nothing on this phone can start it again — the Mac has to. So the phone asks first.
    case exit

    public var label: String {
        switch self {
        case .cancel: "Stop this run"
        case .compact: "Compact the conversation"
        case .clear: "Clear the conversation"
        case .exit: "End the session"
        }
    }

    public var symbol: String {
        switch self {
        // Filled, not outlined: this is the one you reach for while something is
        // running, and an outline of a stop sign reads as a suggestion.
        case .cancel: "stop.circle.fill"
        // Says what compacting does to the conversation — folds it — where the old
        // four-arrow glyph was the generic "make this smaller" from a window chrome.
        case .compact: "rectangle.compress.vertical"
        // The only irreversible thing in the app, and an eraser did not say so.
        case .clear: "trash"
        // Out through a door, which is what this is. Not `power`, which reads as the Mac.
        case .exit: "rectangle.portrait.and.arrow.right"
        }
    }

    /// True for the ones that cannot be undone.
    public var asksFirst: Bool { caution(about: "") != nil }

    /// What the phone asks before doing one of those, or nil where there is nothing to ask.
    ///
    /// The words live on the control rather than in the dialog, because the dialog is one dialog
    /// for all of them: a second control that needed confirming found a sheet that could only say
    /// "Clear", and the way that bug does not happen twice is for the control to carry its own
    /// question.
    public func caution(about name: String) -> Caution? {
        switch self {
        case .cancel, .compact:
            nil
        case .clear:
            Caution(title: "Clear \(name)?",
                    verb: "Clear the conversation",
                    because: "Everything said in this session goes. There is no undo.")
        case .exit:
            Caution(title: "End \(name)?",
                    verb: "End the session",
                    because: "Claude Code quits and the session leaves the rail. "
                        + "Only the Mac can start it again.")
        }
    }
}

/// What is asked before a control that cannot be undone: the question, the words on the button
/// that goes through with it, and what it costs.
public struct Caution: Sendable {
    public let title: String
    public let verb: String
    public let because: String

    public init(title: String, verb: String, because: String) {
        self.title = title
        self.verb = verb
        self.because = because
    }
}
