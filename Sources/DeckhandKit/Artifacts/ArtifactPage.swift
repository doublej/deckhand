import Foundation

/// What goes in front of a page before any web view is allowed to see it.
///
/// This is the security boundary of the whole feature, and it is deliberately string work and
/// nothing else: no web view, no UIKit, no iOS. A pure function can be tested on the Mac, and
/// the one thing here that must never silently stop working is the policy arriving ahead of the
/// page's first script.
///
/// Two things are injected, in this order:
///
/// 1. The CSP from `docs/artifacts.md`, as a `<meta http-equiv>`. A page may declare its own;
///    browsers *intersect* policies rather than replacing them, so ours can only narrow what a
///    page may do and a page cannot widen itself out of it.
/// 2. Deckhand's own stylesheet, so a page that writes plain semantic HTML already looks like
///    the app. It goes first so the page's own `<style>` comes later in the cascade and wins —
///    the tokens are a starting point, not a cage.
public enum ArtifactPage {
    /// The policy, copied from `docs/artifacts.md` and not re-derived. No network of any kind:
    /// no CDN, no web font, no `fetch`, no remote image, no form post, no navigation.
    public static let policy = """
    default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; \
    img-src data:; font-src data:; form-action 'none'; base-uri 'none'
    """

    /// The name the page's messages arrive under. One handler, two kinds of message.
    public static let handlerName = "deckhand"

    /// The page, with the policy and the stylesheet in front of it.
    ///
    /// Everything is prepended rather than spliced into `<head>`, which reads like the cruder
    /// option and is the stricter one. A meta element before the page's own `<html>` is put into
    /// the implicit head by the HTML parser — first, ahead of anything the page wrote, whatever
    /// the page did with its own `<head>`. Searching for `<head>` and inserting after it loses
    /// that guarantee for exactly the page that matters: one that opens with a `<script>` before
    /// any head tag gets its script hoisted into the head *above* the injection, and runs
    /// unpoliced. The parser's own rules make the first token win, so the first token is ours.
    ///
    /// The doctype is the one thing that must stay in front of the injection: anything before it
    /// puts the page into quirks mode, where the stylesheet would be laying out against
    /// different box rules than it was written for. A page with no doctype is given one for the
    /// same reason.
    ///
    /// No `charset` concern, and this is why the bytes are handed over as a `String`:
    /// `loadHTMLString` takes text that has already been decoded, so a page's own
    /// `<meta charset>` being pushed past the first 1024 bytes by the stylesheet cannot
    /// mis-decode anything.
    public static func armoured(_ html: String, style: String = ArtifactStyle.css) -> String {
        let (doctype, rest) = parted(html)
        return """
        \(doctype)
        <meta http-equiv="Content-Security-Policy" content="\(policy)">
        <style>
        \(style)
        </style>
        \(rest)
        """
    }

    /// The page's own doctype and everything after it, or a doctype of our own and the lot.
    private static func parted(_ html: String) -> (doctype: String, rest: String) {
        // A byte-order mark is not whitespace, and left in place it would sit between the
        // doctype and the injection.
        let text = html.drop { $0.isWhitespace || $0 == "\u{FEFF}" }
        guard text.prefix(9).lowercased() == "<!doctype", let close = text.firstIndex(of: ">") else {
            return ("<!DOCTYPE html>", String(text))
        }
        return (String(text[...close]), String(text[text.index(after: close)...]))
    }

    /// `window.deckhand`, as the page sees it: the two things it can do and the two things it
    /// can know. Injected at document start, so it is there before the page's first line runs.
    ///
    /// Frozen and non-configurable, because a page that overwrites `window.deckhand.respond`
    /// with its own function has quietly broken the only way a person's answer gets off the
    /// screen, and nothing would say so.
    ///
    /// The value is stringified on the page's side rather than handed over as an object. A
    /// message body arrives in Swift as loosely typed dictionaries and arrays that then have to
    /// be turned back into JSON; one `JSON.stringify` here means the value crosses as text and
    /// is parsed exactly once, on the far side, where it can be refused.
    ///
    /// `respond()` with nothing, or with `null`, throws in the page rather than travelling. The
    /// Mac refuses an answer of `null` on purpose — a missing field and an explicit null are the
    /// same thing to it, and the absence of the answer file already says "unanswered" — so a page
    /// that does this has a bug, and a `TypeError` in the page's own console is where the agent
    /// that wrote it will look. `false`, `0`, `""` and `[]` are answers and go as they are.
    ///
    /// `answer` is what the person said last time, as the JSON text of the value, or `null` where
    /// nobody has. A page that was answered and then reopened drew itself blank while the row above
    /// it said "answered", and both cannot be true — so the previous value is here, in the page's
    /// own shape, because the page is the only thing that knows how to put its answer back into its
    /// own controls. It is not frozen, unlike `artifact`: a page prefills its controls from it and
    /// then the person edits, and a frozen object would throw the moment one did.
    public static func bridge(for artifact: Artifact, answer: String = "null") -> String {
        """
        (function () {
          const post = (payload) => window.webkit.messageHandlers.\(handlerName).postMessage(payload);
          Object.defineProperty(window, 'deckhand', {
            value: Object.freeze({
              artifact: Object.freeze(\(described(artifact))),
              answer: \(literal(answer)),
              respond: function (value) {
                if (value === undefined || value === null) throw new TypeError('deckhand.respond(value) needs a value; null is not an answer');
                post({ kind: 'respond', json: JSON.stringify(value) });
              },
              close: function () { post({ kind: 'close' }); }
            }),
            writable: false,
            configurable: false,
            enumerable: true
          });
        })();
        """
    }

    /// What the app watches a page for, so that a control can appear when the page is holding
    /// something worth talking into or about.
    ///
    /// Two facts and **only** two, both booleans in effect: something is selected, or a field has
    /// focus. Never the text. A message handler is reachable from any script on the page, so
    /// anything a page says about itself is a claim — and a page that could claim a selection it
    /// does not have could put words in somebody's mouth on the review card. What these reports
    /// can do at worst is show a control that then has nothing to work on. The passage itself is
    /// read out of the page by the host, at the moment it is wanted.
    ///
    /// Its own script rather than part of the bridge: the bridge is the page's own API, and this is
    /// the app's eyes. A page can remove these listeners and lose itself the control, which is the
    /// same deal as a page that paints nothing losing itself a screen.
    ///
    /// Every look is deferred a turn. `focusout` arrives *before* the focus it is losing has landed
    /// anywhere, so reading the document mid-change reports nothing focused for an instant — which
    /// is a control blinking out and back every time a thumb moves between two fields.
    ///
    /// A password field is deliberately not a field here. Dictation goes to the Mac and back; a
    /// password does not make that trip.
    public static let watcher = """
    (function () {
      let last = '';
      const look = () => {
        const at = document.activeElement;
        const typing = !!at && (at.tagName === 'TEXTAREA' || at.isContentEditable
          || (at.tagName === 'INPUT' && /^(|text|search|url|email|tel|number)$/i.test(at.type)));
        const holds = typing ? 'field' : (String(window.getSelection()).trim() ? 'quote' : 'none');
        if (holds === last) return;
        last = holds;
        window.webkit.messageHandlers.\(handlerName).postMessage({ kind: 'holds', holds: holds });
      };
      const soon = () => window.setTimeout(look, 0);
      document.addEventListener('selectionchange', soon);
      document.addEventListener('focusin', soon);
      document.addEventListener('focusout', soon);
      window.addEventListener('pageshow', soon);
    })();
    """

    /// One JSON value, or `null` where there is nothing to put there.
    ///
    /// The text is interpolated into the bridge as a JavaScript expression, so empty text would
    /// leave `answer: ,` — a syntax error that takes `window.deckhand` with it and loses the
    /// page its only way to answer at all. Emptiness is the one thing that cannot be checked on
    /// the far side, so it is checked here. What the text *says* is the client's to guarantee: it
    /// re-serialises the Mac's answer rather than forwarding the bytes, so this is already JSON
    /// the phone has parsed.
    private static func literal(_ json: String) -> String {
        let text = json.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "null" : text
    }

    /// `{id, title}` as a JSON literal. Built by the encoder rather than by interpolation: a
    /// title is whatever an agent typed, and a quote or a newline in one would otherwise end
    /// the object early and take the rest of the bridge with it.
    private static func described(_ artifact: Artifact) -> String {
        let fields = ["id": artifact.id, "title": artifact.title]
        guard let data = try? JSONSerialization.data(withJSONObject: fields),
              let text = String(bytes: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
