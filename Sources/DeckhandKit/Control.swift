import Foundation

/// The things you do *to* a session rather than say to it. Each is a keystroke in its pane on
/// the Mac, exactly as it would be typed by hand.
///
/// The raw values are the wire words `deliver.CONTROLS` is keyed by on the Mac, and nothing joins
/// the two lists but the spelling — `ControlTests.wire` and the daemon's own
/// `test_every_control_the_phone_offers_is_one_the_daemon_knows` are the join, one from each end.
///
/// Split out of `Models.swift` when `exit` pushed that file past 300 lines. It earns a file:
/// three of these are worth a question and two of them cannot be undone, and what the phone says
/// before doing one is here with the control rather than in the sheet that shows it.
public enum Control: String, CaseIterable, Sendable {
    /// Escape: stop what it is doing now.
    case cancel
    /// `/compact`: fold the conversation so far into a summary and carry on. The detail under
    /// the summary does not come back, so the phone asks first — but the session carries on,
    /// which is what keeps this out of the set `isIrreversible` names.
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

    /// True for the ones the phone puts a question in front of.
    public var asksFirst: Bool { caution(about: "") != nil }

    /// True for the ones nothing can bring back.
    ///
    /// **Not the same set as `asksFirst`, and the split is the point.** It was one property doing
    /// both jobs while the two sets happened to be equal. Compacting asks first — it costs the
    /// detail of everything said so far — and it is still a session carrying on with what it
    /// kept, where `clear` and `exit` leave nothing to carry on from. This is the set the session
    /// menu draws red in its own section and keeps off the dashboard, because a grid of identical
    /// squares is where a thumb moves fastest; asking first is a sentence and a second tap, which
    /// is a different price.
    public var isIrreversible: Bool {
        switch self {
        case .cancel, .compact: false
        case .clear, .exit: true
        }
    }

    /// What the phone asks before doing one of those, or nil where there is nothing to ask.
    ///
    /// The words live on the control rather than in the dialog, because the dialog is one dialog
    /// for all of them: a second control that needed confirming found a sheet that could only say
    /// "Clear", and the way that bug does not happen twice is for the control to carry its own
    /// question.
    public func caution(about name: String) -> Caution? {
        switch self {
        case .cancel:
            nil
        case .compact:
            Caution(title: "Compact \(name)?",
                    verb: "Compact the conversation",
                    because: "Everything said so far is folded into one summary. What it kept is "
                        + "what it carries on with; the detail underneath is gone.")
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

    /// Drawing a line under a session's inbox.
    ///
    /// Not a `Control` — it is a file the daemon writes rather than a keystroke in a pane — so
    /// the words live here rather than on that enum, and for the same reason they live *with*
    /// the action rather than in the dialog: the one thing this type exists to stop is a sheet
    /// that can only say "Clear".
    ///
    /// **What it costs, and nothing more than that.** The daemon writes a timestamp and the
    /// replay starts after it; Claude Code's own transcript is never touched. So the sentence
    /// says the waiting prompts are dropped and says the conversation is fine, which is the
    /// truth — borrowing `clear`'s "there is no undo" would be a scarier sentence about a
    /// smaller thing, and somebody who believed it once would stop believing the other one.
    public static func clearingInbox(of name: String) -> Caution {
        Caution(title: "Clear \(name)'s inbox?",
                verb: "Clear the inbox",
                because: "Prompts still waiting are dropped and the session will never read "
                    + "them. What it has already said is untouched.")
    }
}
