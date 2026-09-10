# DeckhandKit

## What this is

The half of the app that runs on the Mac: the models, the HTTP client, the pure logic and the
design layer. Everything here is reachable by `just test` — which is why anything that can go
wrong without a screen belongs here rather than in the app target. `Fitting`, `Grouping`,
`Markup` and `Underneath` are all in this folder for that one reason.

Every file opens with a doc comment saying what it is for; read that rather than a map here.
Design is its own packet (`Design/CLAUDE.md`).

## Invariants

- **`convertFromSnakeCase` rewrites dictionary keys too, not only struct keys.** A filter taking a
  `max_words` setting would be handed back `maxWords`, a key it has never heard of, and the
  setting would silently vanish. So `filters()` and `saveFilters()` decode through a decoder with
  no key strategy while the rest of the client keeps the conversion. Nothing on the filters wire
  is snake case, so nothing is lost either way; a test asserts `max_words` survives a real call.
- **The settings document decodes with no key strategy, and the reason is worse than filters'.**
  `convertFromSnakeCase` rewrites dictionary keys, and the keys of `Settings.projects` are folder
  paths — this tree has `_archive` and `_sandbox` in it, so `/dev/_sandbox/my_thing` would arrive
  renamed and the override filed under it would be gone. `session_model` and `summary_model` are
  spelled out in `CodingKeys` instead, which buys a second thing: the converting decoder then
  cannot find them and *throws*, so the mistake is loud rather than a document quietly missing
  its overrides. A test asserts both halves.
- **`delivered: true` is not the same as "it was said".** The daemon can answer `delivered: true`
  alongside a filter's stop, so every screen asks `Delivery.went` — `delivered && stoppedBy == nil`
  — and never `delivered` alone.
- **Favourites and the hidden set are keyed by name**, so `Preferences.renamed(from:to:)` has to
  carry them or a starred session silently loses its star on a rename.
- **Never call a public type `Context` in this module.** Inside a `UIViewRepresentable`, `Context`
  is already a typealias for `UIViewRepresentableContext<Self>`, so a module-level `Context`
  imported beside SwiftUI silently breaks the conformance of anything spelling
  `makeUIView(context:)` the documented way — and the error names the representable, not the
  clash. It is `ContextWindow`.
- **A local host has no meaning on a phone.** `Links` marks bare URLs with `NSDataDetector` in
  both a turn and the summary's prose, leaving anything markdown already linked alone; the tap on
  a local address is intercepted (`LocalLinks`, in the app target) and offers the Mac instead —
  the address it reports for itself (`/health`'s `lan`) and the one this phone is already reaching
  it on. Both, because neither is reliably the right one.

## Artifacts — say slip, write artifact

- **An artifact is a "slip" to the person holding the phone.** The tab says SLIPS, the row says
  "1 of 3 slips waiting", and the message a session gets back says "Answered the slip …". The
  folder (`.deckhand/artifacts/`), the endpoints (`/sessions/{id}/artifacts`) and `artifacts.py`
  keep the older word, because renaming a path every agent already writes to buys nothing —
  "page" in that code means the HTML itself.
- **`ArtifactPage.policy` is the security boundary**, and host-initiated script is not what it is
  about. `evaluateJavaScript` and `callAsyncJavaScript` run in the page's world as the app asking
  the document a question, not as script the page loaded — and the policy allows inline script
  anyway, which is how the bridge runs at all. So reading a selection out of a page and laying
  dictated words into its focused field needed nothing loosened, and nothing there is to be
  loosened for anything else either. What a page *says about itself* over the message handler is a
  different matter: any script on the page can post to the handler, so `holds` carries no text. A
  page could claim a selection it does not have; at worst that shows a control with nothing to
  work on, because the passage is read out of the page by the host at the moment it is wanted.
- **A slip can declare its questions instead of only drawing them**, and then it is not a web page
  at all: `Aloud` parses one `id="deckhand-aloud"` JSON block out of the HTML and the app draws a
  card per question with the app's own talk mark on it. Parsed here as string work rather than
  asked of a live web view — the app already holds the page as a string, and this way the aloud
  path builds no web view and the whole decision is testable on the Mac. Every failure lands on the
  same side: no block, bad JSON, no usable question → `declared` is nil → the HTML renders. The
  answer is the *form* shape (`{"answer": {id: words}, "completedCount": n}`) on purpose, so
  nothing new has to be learned to read one.
- **A custom item cannot be added to a `WKWebView`'s text-selection menu on iOS 18.** Measured
  against the iPhoneOS 26.5 SDK headers, because every route that sounds right is a dead end:
  `WKUIDelegate.webView(_:willPresentEditMenuWithAnimator:)` hands over a
  `UIEditMenuInteractionAnimating`, whose entire protocol is `addAnimations(_:)` and
  `addCompletion(_:)`. WebKit exposes no equivalent of `UITextViewDelegate`'s
  `editMenuForTextIn:suggestedActions:`. UIKit builds the edit menu with
  `menuElementsFromResponderChain:…:includeMenuControllerItems:`, so the only way in for a custom
  selector is the deprecated `UIMenuController.menuItems` bridge, gated by a private
  `_includeMenuControllerItems` flag that WebKit never sets. `UIContextMenuSystem`, which would be
  the supported answer, is iOS 26. So the app's own surface is the answer: `ArtifactPage.watcher`
  reports *that* there is a selection and `SayOnPage` appears under the page. Reconsider when the
  floor reaches iOS 26.

## Verification

- **`StubProtocol` is static, and suites run in parallel.** A second `@Suite` stubbing the same
  transport answers the first one's requests — measured: a `/projects` body arrived at the
  `/sessions` test and both failed. `.serialized` orders tests *within* a suite, not across them.
  Anything that stubs the client goes in `ClientTests` — including as an `extension ClientTests`
  in another file, which stays in that suite and so stays serialized with it.

`just test` runs `Tests/DeckhandKitTests` on the Mac — no simulator needed.
`.quality.json` caps a Swift file at 400 lines and a directory at 16 files, which is why
`DeckhandClient+Filters.swift` and `Conversation.swift` exist.

## Related context

- `Design/CLAUDE.md` — the design language, ported from utt
- `../../docs/artifacts.md` — what a slip is, what it may contain, and the bridge
- `../../.claude/rules/swift-naming.md` — the two naming traps this module has hit
