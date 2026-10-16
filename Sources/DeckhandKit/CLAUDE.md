# DeckhandKit

## What this is

The half of the app that runs on the Mac: the models, the HTTP client, the pure logic and the
design layer. Everything here is reachable by `just test` — which is why anything that can go
wrong without a screen belongs here rather than in the app target. `Fitting`, `Grouping`,
`Markup` and `Underneath` are all in this folder for that one reason.

Every file opens with a doc comment saying what it is for; read that rather than a map here.
Design is its own packet (`Design/CLAUDE.md`).

## Invariants

- **`ManagerRole` decodes an unknown role as `.note` rather than throwing.** The Mac is upgraded
  by a git pull and the phone by a rebuild, so they are routinely a version apart — and a daemon
  that grows a sixth kind of entry would otherwise take the whole conversation down on a phone
  nobody has rebuilt. The text of that entry is still worth reading whatever kind it is. Same
  argument `Turn`'s tolerant decoder is written for, one level down.
- **`Provider` decodes an unknown word as `.claude`, and a row with no key has `provider == nil`,
  which is Claude too.** `ManagerRole`'s argument again: a Mac that grows another provider must
  not take the listing down. Views ask a capability — `stops`, `compacts`, `renames`,
  `endsByKeys`, `takesCommands`, `hasInbox`, `hasContextTree`, `isOnTheMac` — and `providerWord` for
  the label, never the raw word, so a fourth provider is a change in `Listing.swift` alone.
- **A state word is `session.runState`, never `isBusy ? .busy : .idle`.** An OpenCode session
  stays listed for two hours after a TUI closed it, and `in_client: false` is how the Mac says so;
  `runState` turns that into OFF, and `contrast` puts the row at the floor. A missing key is open,
  which is every Claude and Codex row and every Mac older than the field.
- **`ManagerFeed.newest` is the cursor, never `entries.last?.id`.** A poll that brought nothing
  back still has to leave the phone asking for the right thing, or the next one re-fetches the
  whole conversation. A test holds it down.
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
- **`UploadReceipt` is the one type here with a hand-written `CodingKeys`, and one key is why.**
  utt calls its rewrite stages `stages`, and the receipt already has stages of its own under
  `timings` — so `uttStages` is spelled `case uttStages = "stages"` and every sibling had to be
  listed with it. The Mac's own stages travel as a **list** of `{name, ms}` rather than an object
  for the `convertFromSnakeCase` reason above: a stage name is data, and a key would be rewritten.
- **`raw` is from before *everything*, hints included, so a rewrite is attributed off `stages`.**
  utt's pipeline runs `hints` between `raw` and `text`, and those hints are this repo's own
  vocabulary (`transcribe.VOCABULARY`). Comparing the two strings and naming utt would tell
  somebody utt's cleanup rewrote "deck hand" when the word came out of a list in this codebase.
  `Rewrites` therefore names the stages utt reported and nothing else, and `uttRewrote` is
  `raw != nil && !uttStages.isEmpty` — the same test as utt's own `ProcessedTranscript.changed`,
  which also keeps whitespace from reading as a rewrite.
- **A stage being timed and a stage having changed the words are two questions.** utt reports
  a timing for anything that *ran* and lists in `stages` only what *changed the words*, so the
  breakdown may honestly show a stage `stages` never mentions. `ClipTiming.verdict(on:)` is the
  only sentence allowed beside one: "unchanged", never "reviewed" or "approved" — absence from
  `stages` says the words came out the same and says nothing about a stage having looked.
- **What a clip cost is `ClipTiming`, and it is assembled on the phone.** The Mac measures its own
  stages, the recorder and the upload measure the phone's, and `ClipTiming.merged` puts them in
  the order the clip travelled. The network is *derived* — the upload span with the Mac's total
  taken out of it — because nothing on the phone can see when its request arrived; it is clamped
  at zero, since the two clocks are different clocks. `spoken` is beside the stages and not among
  them: a breakdown dominated by however long somebody talked says nothing about what is slow.
  A `Stage` nests: utt's span carries its own stages as `children` (wire key `inside`) when utt
  measured them, and stands alone when it did not.
- **`delivered: true` is not the same as "it was said".** The daemon can answer `delivered: true`
  alongside a filter's stop, so every screen asks `Delivery.went` — `delivered && stoppedBy == nil`
  — and never `delivered` alone.
- **A beacon's addresses are in its TXT record, and the browse is what reads them.**
  `Finding/Beacon.swift` browses with `NWBrowser.Descriptor.bonjourWithTXTRecord`, so the metadata
  arrives on the browse result and nothing is resolved — opening an `NWConnection` to an
  `NWEndpoint.service` to read `currentPath.remoteEndpoint` buys one IP address, where what is
  wanted is the Mac's own pair in its own order. Both are checked through
  `ServerSettings(host:).baseURL`, so a tap can only ever fill the Address field with something
  that field would have accepted typed, and a Mac that could work out only one of the two is a
  beacon with one candidate rather than no beacon. The same Mac is heard once per interface it is
  reachable on — measured, `if 1` and `if 17` on this network — so results are keyed by address.
- **Which of the two goes in is asked, not guessed — but only one of them is asked.**
  `Beacon.answering` calls `/health` on the `.local` name and takes the IP when that fails: the
  question is whether this phone's link resolves the name, which is a fact about the phone and
  not about the Mac, and it is askable at pairing time only because `/health` is the one route
  with no token on it. **The IP is deliberately never probed**, and the measurement is the
  argument: in the simulator on 2026-09-14 a first connection to a raw private address came back
  `-1001` timed out at five seconds while the same address connected fine through
  `DeckhandClient`'s twenty — so a probe quick enough to sit under a thumb rejects a working
  address, and one patient enough to be right is twenty seconds of dead tap. A fallback that must
  prove itself before it may be used is not a fallback, and both ways of being wrong here are
  cheap: the IP reaches the same daemon, and a dead address is what the Connection row is for.
- **`Looking` has five cases because three of them are kinds of silence.** Still browsing, heard
  nothing, and refused permission are different facts, and on iOS a refused local network
  permission browses silently forever — so a single "no results" would tell somebody there is no
  Mac when the truth is that this phone would not look. `ServerSettings.adopts` carries the same
  distinction as a `Bool?`: nil is "nobody asked", which is not a failure and never moves an
  address somebody typed.
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
