import DeckhandKit
import Foundation
import WebKit

/// What the app can see of a slip, and the two things it can say back to one.
///
/// The page reports only *that* it is holding something — `ArtifactPage.watcher`, and the reason it
/// reports no text is written there. Everything with words in it happens here, host-side, by asking
/// the page directly: the passage is read out of it when the person starts talking, and dictated
/// words are laid into its focused field afterwards.
///
/// Host-initiated script is not what the policy in `ArtifactPage` is about. That policy governs what
/// the *page* may load and run — and it already allows inline script, which is how the bridge runs at
/// all. Reading a selection and setting a field's value are the app asking the document questions in
/// its own world; nothing here needs `eval`, nothing here fetches, and nothing about the policy was
/// touched to make it work.
///
/// Lives as long as the screen, which is why the view owns it and not the web view: the page is held
/// weakly, so this outliving a torn-down web view costs nothing and the web view is never kept alive
/// by the screen's state.
@MainActor
@Observable
final class PageTalk {
    /// What the page has that can be spoken into, or about. Nothing, by default and between things.
    enum Holds: String { case none, quote, field }

    var holds: Holds = .none

    /// The page itself, handed over once by the web view that made it.
    ///
    /// Ignored by observation on purpose. It is set while the web view is being made, which is in
    /// the middle of a SwiftUI update, and a tracked write there is the "modifying state during
    /// view update" warning. Nothing draws from it, so nothing needs to hear about it.
    @ObservationIgnored weak var web: WKWebView?

    /// What the person has selected, read out of the page rather than taken from it.
    ///
    /// Asked for at the moment the person starts talking, not when the words come back: a tap
    /// somewhere else in the page clears a selection, and the answer has to be in hand before
    /// anything else can take it away.
    func passage() async -> String {
        let said = try? await web?.evaluateJavaScript("String(window.getSelection())")
        return (said as? String) ?? ""
    }

    /// Dictated words into whichever field the page has focused, under whatever it already holds.
    ///
    /// Under, never over — the same rule as every field in the app, through the same tested
    /// `Underneath.words` rather than a second copy of it in JavaScript. Which means reading the
    /// field first: two round trips into the page, because the joining is Swift's.
    ///
    /// A real `input` event after the write, or the page never hears about the words. Every one of
    /// the demo slips gates its own button on `input`, so a value set behind a page's back is words
    /// that are visibly there and count for nothing. `change` is deliberately *not* sent: it means
    /// the person has finished with the field, and they have not — they can say more, or type.
    func say(_ said: String) async {
        guard let web, let held = try? await web.evaluateJavaScript(Self.reading) as? [String: Any],
              let standing = held["held"] as? String else { return }
        let gap = (held["multi"] as? Bool) == true ? "\n\n" : " "
        _ = try? await web.callAsyncJavaScript(
            Self.writing,
            arguments: ["words": Underneath.words(said, under: standing, gap: gap)],
            contentWorld: .page
        )
    }

    /// The focused field's value, and whether it is the kind that takes more than one line.
    ///
    /// `innerText` for something editable in place, `value` for a real control. A field with neither
    /// answers nothing and the words stay on the phone, which is the honest end of a page that
    /// changed what it was focusing while a clip was in the air.
    private static let reading = """
    (function () {
      const at = document.activeElement;
      if (!at) { return null; }
      const multi = at.tagName === 'TEXTAREA' || !!at.isContentEditable;
      const held = at.isContentEditable ? at.innerText : at.value;
      return typeof held === 'string' ? { held: held, multi: multi } : null;
    })()
    """

    /// The joined words back into the field, with the caret left at the end of them.
    ///
    /// The words arrive as an argument rather than interpolated into the source. A transcript is
    /// whatever somebody said — quotes, backslashes, newlines and all — and escaping it by hand to
    /// survive being read as JavaScript is a bug waiting for the first person to dictate an
    /// apostrophe. `callAsyncJavaScript` passes it as a value, so there is nothing to escape.
    private static let writing = """
    const at = document.activeElement;
    if (!at) { return; }
    if (at.isContentEditable) { at.innerText = words; } else { at.value = words; }
    if (at.setSelectionRange) { at.setSelectionRange(words.length, words.length); }
    at.dispatchEvent(new Event('input', { bubbles: true }));
    """
}
