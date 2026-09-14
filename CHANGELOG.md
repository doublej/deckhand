# Changelog

Every commit on `develop`, 2026-09-09 13:14 through 2026-09-10 15:27. 143 commits, 52 on the
first day and 91 on the second, five of them merges. Written from the commit bodies; anything
about the current tree was checked against the tree.

Nothing has been released. `main` still holds the scaffold commit alone, so everything below is
one unreleased span. Sibling documents: [docs/features.md](docs/features.md) is what the thing
can do today, [docs/history.md](docs/history.md) is how it was asked for.

## The shape of the two days

Day one built the thing end to end and then rebuilt its two load-bearing lanes underneath
itself. Day two was mostly the phone: filters, slips, pictures, projects, and a long tail of
reading — thinking blocks, older turns, the CLAUDE.md tree — plus the documentation split that
made the repo legible to the agents working in it.

Phases, in the order they landed: scaffold and first bridge (`7b260ed`–`dc70423`) → the daemon
learns to transcribe and summarise (`804a21f`) → the route argument, settled (`d05e2b4`) → the
design layer ported from utt (`1801950`) → App Store and Lock Screen (`38908eb`, `57c2e5a`) →
reading a session properly (`17c7136`, `551c878`, `32e6a86`) → filters (`37d2667`) → slips
(`c33c8da`) → pictures and marks (`a1f42da`) → prompts as files and Haiku (`b1e85d0`,
`33386d1`) → the CLAUDE.md tree split (`82a2e18`) → projects and per-folder settings
(`ea01ddf`, `3298cc6`) → navigation stripped back to swiping (`9f514b3`, `8ae7b54`).

The four biggest turns:

1. **The route stopped being a transport and became an authority choice** (`d05e2b4`). The peer
   socket worked (`2c782be`) but the receiver wraps anything arriving there as another agent's
   words carrying none of the person's authority. Rather than defeat that wrapper, the words go
   in through the keyboard — `it2 session run` types them into the pane. The socket stays as the
   fallback for a session with no pane, and the choice became explicit in Settings (`8208f5e`),
   with `keyboard` never silently falling back.
2. **Transcription moved off utt's HTTP API onto its file lane** (`6ecd850`). A clip is written
   into utt's own jobs folder and the text appears beside it. That deleted a token, a 1Password
   sync recipe and a whole class of "the clip came back empty" — and it deleted the menu bar app
   with it (`781c153`), because Deckhand's page inside utt covered three of its four buttons.
3. **The Mac took ownership of the expensive things.** Briefings went from an in-memory cache
   with a two-minute TTL to files written by one worker, gated on mtime then on an activity hash,
   with `GET /briefings` for a cold start (`32e6a86`). The ask list moved off the briefing and
   onto disk behind three SDK tools (`d0f5571`). Filter chains moved from one global chain to one
   per terminal, keyed by name (`002dea1`).
4. **Root CLAUDE.md became a map and nine context packets** (`82a2e18`), with GLOSSARY.md as the
   project's vocabulary — 554 lines and ~18k tokens paid at every session start, reduced to the
   folder where each fact is true.

### Branch state

`main` is at `7b260ed`, the scaffold commit, and is **142 commits behind** `develop`. Nothing on
`main` is absent from `develop`. There are no tags and no releases, so the `develop` → `main` →
annotated tag half of the branch flow has never been run for this repo.

---

## 2026-09-09

### Scaffold, first bridge, first install

- `7b260ed` **scaffold** — Justfile, `.quality.json` (400-line file cap, 16-file directory cap),
  SwiftLint config, `agent.md`, verify-runner agent, template hooks, one `App.swift`. Still the
  tip of `main`.
- `c0f9574` the daemon: sessions listed by joining `~/.claude/sessions/<pid>.json` with `ps` and
  `it2 session list`, the tail of each transcript, and clip storage. Token-gated, port 4180.
- `675a149` the iOS app and DeckhandKit — models, HTTP client and server settings testable on the
  Mac; deck of sessions, last rounds, hold to talk.
- `78d1bc0` task runner, the launchd plist, project docs.
- `dc70423` **merge** — phase 1 bridge, joining the three commits above.
- `95ccc8c` `install-agent` waits for the daemon instead of sleeping once.
- `da63a6e` cache the iTerm pane lookup; stop waiting 10s on approval.
- `8bed0c8` ignore run reports.
- `7e176ad` install on a phone: deployment target drops to iOS 18, `just device` builds, installs
  and launches with host and token as launch arguments, written back to defaults.
- `d921d84` `devicectl` needs `--` before the app's own flags, or it exits 64 — `just device`
  installed and then failed to launch.

### Transcription and summaries

- `804a21f` utt turns each clip into text; summaries come from the Claude Agent SDK (sonnet, low
  effort, no tools, `setting_sources=[]` because loading them started every MCP server the user
  has). One log under `~/Library/Logs/Deckhand`. A failed iTerm lookup says so in an `iterm`
  field and backs off for a minute rather than paying its 4s timeout per request.
- `a85f2a9` say "utt is closed" instead of printing errno 61.
- `7f39574` docs correction: toggling utt's API does not re-mint its token — the retry-on-401
  stands, but the cause named was wrong.
- `6ecd850` **the file lane replaces the HTTP API.** Clip goes into utt's own jobs folder,
  utt writes the text beside it. No listener, no token, nothing on the network; 0.9s end to end.
  Deletes the token read out of utt's settings.json, `UTT_SECRET`, the materialised copy and
  `just sync-secrets`. Adds transcription hints (session name, folder, product vocabulary) and
  `plugin.py`, Deckhand's page inside utt.
- `781c153` **delete the menu bar app** added at `b60579b` the same afternoon. Three of its four
  buttons are actions on the utt page; the fourth is utt's own Restart, which reads live launchd
  state. Removes the `DeckhandMenu` target, its scheme, `just menubar` and an xcodebuild step.
- `4132e29` docs: the plugin page needs utt 1.1.0; values arrive per keystroke.
- `276c271` Deckhand's actions in utt's menu bar — but not "Stop listening": `showsInMenuBar` is
  all actions or none, and `launchctl bootout` cannot be undone by utt's `kickstart` (verified,
  exit 113). Needs utt ≥ 1.1.0 for the `isSafeKey` fix.

### The route

- `2c782be` the peer socket: auth line with the `peerToken` beside the session record, then a
  user frame at priority `next`. Verified against a live session, not only the test socket.
- `d05e2b4` **keyboard route**, and with it the invariant this project now rests on. Also: panes
  work under launchd after all — the plist asked for `ProcessType: Background`, so a ~1s lookup
  missed its 4s timeout every time; `Interactive` and 12s resolved all nine sessions. Summary
  client timeout 20s → 75s.
- `3ad957b` type in three bursts — ctrl-U, the words, return alone — because a return at the tail
  of a fast paste is read as pasted text and leaves the message staged. No read-back is possible,
  so the receipt claims only that the words were typed.
- `8208f5e` route becomes a setting: Auto, Keyboard, Socket. The receipt names the route.
- `8918327` one line of attribution on the socket route, not three.

### Reading a session

- `76938b5` the phone says what it is doing: connection state on screen at all times, and every
  empty list says which empty it is instead of claiming there are no sessions while still asking.
  Star the ones you talk to, hide the ones you do not. Landscape turns the starred ones into
  columns of tiny transcript, holding a whole column talks to it, and a global switch makes
  talking hold-to-speak or tap-to-start. Session identity becomes the sessionId alone — it had
  included status and `updatedAt`, so every four-second refresh replaced every row and a tap
  landed on a view that no longer existed.
- `825bf78` what you said becomes a YOU card in the transcript instead of a bare line under the
  button, dimmed until the session writes it down.
- `646d467` review before sending (`?deliver=false` plus `POST /sessions/{id}/say`), cancel while
  recording, and recording pins the orientation — rotating mid-sentence swapped the view holding
  the recorder and took the clip with it.
- `bd4aa2f` the summary loads beside the transcript rather than in front of it; first load does
  not auto-scroll. The summariser was never broken — 44 summaries in the log — it just had
  nowhere to be seen.
- `f2a71b6` the briefing gets its own tab and `Prose`, which renders exactly the four things the
  summariser is briefed to write and shows anything else as literal characters. Keeps the phone
  awake from the first word to the transcript coming back.
- `6e61537` one header band; hierarchy in the briefing; the approval card at the foot rather than
  last in the transcript; the optimistic copy compared collapsed on the opening 60 characters;
  auto-scroll on first load restored, now that the briefing has its own tab.
- `a601ff9` tool calls stop being dropped on the floor — an assistant entry with no text made no
  turn at all, so a session could work ten minutes and show nothing. Collected and handed to the
  message they led to, drawn as dots that unfold. Tabs move to the foot. `ok` → `succeeded` on
  both sides of the wire at once. `Turn` decodes tolerantly, because the Mac updates by git pull
  and the phone by rebuild.
- `3f7738c` a one-line brief per session on the rail, taken from the briefing rather than bought
  separately; the grey optimistic copy removed outright; tool calls unfold twice; talk control
  becomes a row; a flaky test fixed by waiting on the thread rather than sleeping past the race.
- `12778d2` files tab (the transcript's own paths are the whole permission — an unnamed path is a
  404), the ask list written by the summariser in the same run, and the inbox read from
  `queue-operation` lines.
- `5d4c603` ask marks become boxes, since a round mark is a tool call here.
- `f691555` a rendered video was refused by the 32 MB upload cap; serving gets its own 512 MB cap
  and the phone downloads to a temporary file. Adds stop, compact and clear as keystrokes; clear
  asks first.
- `37438da` the picture viewer becomes a UIScrollView (a SwiftUI ScrollView on both axes proposes
  unbounded space, so `scaledToFit` had nothing to fit to). Adds the context meter, read from each
  assistant entry's usage against Claude Code's own `autoCompactWindow`. `Context` →
  `ContextWindow`, because the bare name collides with SwiftUI's typealias inside a representable.
- `aff1e87` rename a session by typing Claude Code's own `/rename` into the pane; favourites and
  hidden rows, which are keyed by name, are carried across.
- `d0f5571` seven asks at once: press to talk on rows and columns (not a Button — `onLongPress` +
  `onTapGesture`, because the other arbitrations broke the tap or the swipe); chrome to the glass;
  absorbed inbox messages kept and marked taken; and the ask list moves onto the Mac behind three
  SDK tools that may add, set state and drop but never reword, renumber or re-order.
- `1c67c9c` the talk control is the mark alone — the full-width capsule behind it was furniture,
  and an invisible full-width hit slot swallowed taps meant for the page.
- `b500acc` pictures attach as paths, not pastes, accepted only inside the session's own images
  folder. Fixes the raw transcript drawing a black screen (one unwrapped `Text` tens of thousands
  of points wide renders empty with no error).
- `17c7136` `readable.py` — render the transcript as events rather than JSONL, dropping Claude
  Code's own bookkeeping (`attachment` alone was 654 of 1,300 entries in one real day).
- `e6007dc` one live WORKING line at the end of the transcript for as long as the session is busy,
  replacing a pill that vanished the moment the session started running tools.
- `551c878` a message absorbed mid-run is a turn where it arrived — it is written as a
  `queued_command` attachment (149 of them on a live transcript, none also present as a user
  entry). Also: the typed ctrl-U stops riding into a turn's text; a stale inbox can be cleared;
  the idle check that asks a quiet session about unfinished asks arrives over the socket, as an
  agent; **every BUSY badge is removed app-wide**, which is now a standing rule; addresses a
  session writes become tappable.
- `32e6a86` **briefings become files**, one worker, two gates before a model is touched, and
  `GET /briefings` for a cold start. `reading/` and `Controlling.swift` split out at the caps.
- `cda5e66` BRIEF/LIVE per deck column, reading briefings the Mac already wrote. Fixes the rail's
  wordmark sitting behind the clock and the home indicator, and a test whose fake utt gave up
  after 5s while the real code waits 180.
- `60e7c20` the review card holds the whole transcript, scrolling rather than clipping at six
  lines, with an Edit page above the keyboard. Ten SF Symbol names corrected against the real set,
  since a name that does not exist renders as nothing and says so nowhere.

### The look, the icon, the store, the Lock Screen

- `1801950` **the design layer, ported from utt** — ground, type, spacing, the 6×6 dot grid and
  the four-letter state vocabulary, values copied rather than re-picked. Two things are
  Deckhand's own: the tint #3EAFB4 and the anchor mark. The app stops forcing a colour scheme,
  which is what made the rail and the pages one surface.
- `14e642a` the app icon drawn by IconMaker from the same grid (`just icon`). Drops
  `UIUserInterfaceStyle: Dark` from Info.plist, which had been forcing dark at the OS level and
  defeating the change above.
- `4b3c24b` keep the dev-account email out of the tree; gitignore `.claude/tickets/utt-*.md`,
  which carry dictated-voice excerpts and utt's unreleased plugin API docs.
- `38908eb` four App Store blockers: the icon's alpha channel (ITMS-90717), `PrivacyInfo.xcprivacy`
  declaring exactly one required-reason API (UserDefaults, CA92.1),
  `ITSAppUsesNonExemptEncryption`, and one version across both halves. Explicitly not done: the
  bundle id, and `NSBonjourServices`.
- `57c2e5a` **the Lock Screen Live Activity**, pushed from the Mac — a backgrounded app has no
  promise of running again, so the app starts nothing and only hands over tokens. Push-to-start
  only, on the busy → idle transition. This forced the bundle id decision that `38908eb` had
  deferred: push cannot be enabled on a wildcard App ID, so it is `dev.jurrejan.deckhand` now.
  The APNs key is minted by hand and `just sync-apns` materialises it.
- `b60579b` a menu bar app to start, stop and watch the daemon — **removed the same day** at
  `781c153`.
- `b58ec9f` docs: the open list, after delivery and the deck landed.

---

## 2026-09-10

### Filters

- `37d2667` **the filter chain**: `filters/` sits between the phone and `deliver`, `run(Prompt)
  -> Outcome`, over an ordered list where a step is `{filter, on, settings}` and array order is
  run order. First filter swaps words dictation keeps getting wrong. A filter that raises is
  logged and skipped; only an explicit stop ends a chain; a half-written settings file falls back
  to an empty chain. Establishes that **`delivered: true` is not "it was said"** — every screen
  asks `went`. `convertFromSnakeCase` is refused on the filters endpoints because it rewrites
  dictionary keys as well as struct keys.
- `31a25f9` the three endpoints that put something into a session split into their own router,
  mounted with the same token dependency — they are the only ones that hand a prompt to the chain
  before `deliver` sees it, and `_filtered` has no other caller. `app.py` 381 → 230, off the
  warning list. The tests had reached `transcribe` and `deliver` *through* `app.py`'s imports,
  which is what the move broke; they import them directly now. `kinds.py` gains three contract
  notes, including why a list-valued `Field.default` would be shared by every prompt forever.
- `efa638e` a step is a position, not a name: a UUID per row, because index breaks on reorder and
  name resolves both copies of a duplicated filter to the first. A refusal now reads as the Mac's
  own sentence, pulled out of FastAPI's `{"detail": …}`.
- `41cddfb` `prepared` beside `transcript` on a reviewed clip, so the card can show what will
  actually be sent. Marks the ceiling it creates: the chain runs twice for a reviewed clip, free
  for word replacement, wrong for anything non-idempotent.
- `29695c0` the card shows `prepared ?? transcript` with what a filter changed underneath it, in
  hint type, written only through `hold(_:for:notes:)` so a note cannot outlive its words.
- `7cc0ae3` **the craft filter** — hands a dictated sentence to the prompt-crafting skill through
  the SDK's own progressive disclosure (one tool, one model, a system prompt naming a file).
  Forbidden: inventing a requirement, dropping a detail, answering instead of rewriting. Below
  twelve words nothing runs. Every failure returns the words unchanged. This is the first
  non-idempotent filter, which closes the ceiling `41cddfb` marked: `/say` gained `prepared`.
- `002dea1` **a chain belongs to a terminal, not to the Mac.** `filters.json` becomes
  `{"chains": {name: [...]}}`, keyed by session name because an id dies on restart and a cwd is
  shared. The old global chain is dropped rather than copied everywhere (with `craft` in it, that
  would bill a sonnet run per prompt in every terminal) and renamed `filters.global.json`.
  `PUT /filters` is gone — a global chain has no owner to write to.

### Slips

- `c33c8da` **artifacts**: an HTML page a session writes into `<cwd>/.deckhand/artifacts/`, so an
  agent creates one with Write, lists with ls and duplicates with cp. Two files, and the agent
  writes only one; `<title>` is the name. The sandbox is the feature — `default-src 'none'`,
  inline style and script only, no form-action, no base-uri, injected before the page loads, with
  every navigation after the first refused. Path traversal, symlinked slugs and a pre-planted
  symlink answer file were all proved rather than asserted. Five demos match consult-user-mcp's
  own response shapes, and four deliberately broken pages confirm `demo-check` is a gate.
- `d368777` **merge** `feature/artifacts`. Two resolutions, neither behavioural: a comment
  conflict in `DeckhandClient.swift`, and `Design/` coming out at 17 files against a cap of 16 —
  the four artifact files became `Sources/DeckhandKit/Artifacts/`.
- `f6a7c2f` an answered page looks answered (tick, receded title, 72% row) and gains an All /
  Waiting / Answered selector that appears only when there is a mix. Sets tab order to Summary,
  Files, Transcript, Pages — **reordered one minute later** at `7da0397` to Summary, Pages,
  Transcript, Files.
- `888304e` a page waiting on you is visible before you open the tab: `artifacts_waiting` and
  `artifacts_answered` on the session listing, off the same walk the tab reads. Both decode as
  optionals so an older Mac reads as a session with none. A row with a page waiting never fades.
- `be945bf` asks and pages get a line each with a 12pt glyph gutter, instead of thirteen boxes
  running into a page glyph with the meter four points under all of it.
- `ddd9f61` `GET /sessions/{id}/artifacts/{id}/answer` — the value exactly as responded, its own
  request rather than a field on the listing, null rather than an error when nothing answered.
- `94c53fe` the phone half of the same: `window.deckhand.answer`, in place before the page's
  first line runs (answer and HTML fetched together), not frozen because a page prefills and the
  person then edits.
- `3a8b84e` comment on a passage and dictate into a slip's own fields. A selection brings up the
  talk mark; what lands on the card is the passage quoted, the remark under it, and the slip named
  by title and slug — words, not a picture, capped at 1500 characters on a word boundary. A
  focused field gets a Say capsule and a real `input` event, because every demo gates its button
  on one; password fields are not offered it. The CSP was not loosened: the injected watcher
  reports only *whether* there is a selection, never the text.
- `c1b167d` **merge** `feature/page-selection`. Records the abandoned direction in full: there is
  no way to add an item to WebKit's edit menu on iOS 18 — `UIEditMenuInteractionAnimating` can
  animate the menu and not change it, WebKit exposes no `editMenuForTextIn:`, the legacy
  `UIMenuController` bridge is behind a private flag WebKit never sets, and `UIContextMenuSystem`
  is iOS 26. The app's own control above the keyboard is the surface instead.
- `ac4c23e` every demo page now reads `window.deckhand.answer` and prefills from it, which is what
  `docs/artifacts.md` already said a page must do; `pick`'s refresh stops raising the keyboard on
  arrival.
- `fe0be1c` **slip** is the word on the phone — the tab, the row, the empty state, and the message
  the session gets back. The plumbing keeps `artifact`: the folder, the endpoints and
  `artifacts.py` are unchanged, because renaming a path every agent writes to buys nothing.
  `WaitingPage` → `WaitingSlip`.
- `8a82e10` the last four doc comments from `fe0be1c`, held back while another agent had those
  files open.
- `401c3e1` **a slip answered by talking**: a page declares its questions in one JSON block, the
  app draws a card per question with the app's own talk mark, one recorder for the screen. The
  block is the page's only source of truth — `demos/aloud.html` renders itself from it — and every
  way it can be wrong falls back to rendering the HTML.
- `38f426a` a slip's send button has to say it sent. Reported from the phone as "did not
  function": it had functioned, silently, and every re-press sent another answer. Now awaited,
  disabled while sending, and a slip that went closes itself.

### Pictures and marks

- `a1f42da` **mark a picture**: tap a spot, a numbered disc lands, say what is wrong; a pencil
  hands the same picture to PencilKit. Send flattens picture, strokes and numbers into one PNG and
  drops it on the review card. No daemon change at all, by design — `with_images`, `add_image` and
  `AppModel.send` already did each half. Markdown files open as documents with their own renderer,
  because `Prose` deliberately renders only the four things a briefing may contain. Files are
  grouped by suffix, and the commit records that JJ had already called that unusable and asked for
  a selector across the top.
- `ce2eb99` a picture pinned to the card takes the same marks a file does, keyed by the `Snap`'s
  own id so two identical photos cannot bleed into each other. Tap-to-remove is gone from the
  thumbnail — one tap cannot mean both open and lose.
- `d193b1c` `Pin.prose` describes an attachment and names no path, because a pinned picture has
  none until Send uploads it and the Mac renames it.
- `df36240` **merge** `feature/card-pictures` — many photos in one trip, marks on any of them. One
  conflict in `ReviewCard.swift` where both sides were wanted (`say: Dictation?` versus `picked`
  as an array).
- `c7ec08c` the controls come to the hotspot and **PinWords.swift is deleted** — there is no text
  field anywhere in the marking flow. `PictureScroll` reports the chosen marker in its own
  coordinates, so the callout follows through zoom, pan and rotation.
- `bd5ab25` **takes back** the dismiss-on-tap idiom introduced one minute earlier: the single tap
  waits for the double tap to fail, so dismiss-then-drop is a double tap, and marking three places
  would have zoomed twice. One tap is always a new place.
- `fed6643` the callout moves when you choose another place. The position was reported from inside
  `updateUIView`, where a SwiftUI state change is dropped — the first pin only worked because
  dropping it also mutated the binding and bought a second pass. Reports on the next tick and
  carries the pin id.
- `f83c46f` markers go achromatic and double-ringed rather than Deckhand teal, because the picture
  being marked is very often a screenshot of this app.
- `49aa84a` send the unmarked original beside a marked-up attachment — a marker sits on top of the
  thing it is about, and an attachment has no original anywhere else.

### The review card

- `2018bc5` Add: say the rest of it under what is already on the card, never instead of. Both
  append paths live in `Appending.swift`. The chain's note does not survive a second clip; a
  refusal does.
- `5d20fe4` the card's controls become 44pt capsules sharing the width equally, so Discard ends up
  at the opposite end from Send and a label cannot change a button's width.
- `bc971f5` **dictate into any field** — six of them — through one control, `SayInto`, that knows
  about a `Binding<String>` and nothing else. The append rule moves into `Underneath` in the
  package where `just test` can reach it. Words land at the end, not at the caret: SwiftUI on iOS
  18 exposes no insertion point (`TextSelection` is iOS 26). Three fields stay typed, each for a
  stated reason. The rename alert becomes a sheet, because an alert has nowhere to put the mark.
- `5eb39d2` pick a slash command in the review card — 193 commands and skills read off `~/.claude`
  and the project in 46ms, project shadowing user, nested folders keeping their namespace, read
  per request because they are files a person edits. A leading slash alone is not enough to strip.
- `5869b9e` refuse a slash command that would arrive as words: the socket delivers a message, and
  a message beginning with a slash runs nothing and reports no failure, so the phone would show a
  green receipt for a command that never ran.
- `6ecd21b` the foot holds only what you do with a prompt: Photos and Clipboard become one Add
  attachments menu, Add moves under the prompt where its words land, and Discard gives up its fill.

### The session page and its panes

- `db848b3` `SessionHead` splits out of `SessionView` (281 → 170 + 153) on a real seam: who the
  session is and what you do *to* it, versus four interchangeable panes.
- `1d23fdd` end the session from the phone. The confirmation sheet had three string literals about
  clearing a conversation in it, so every control now carries its own `Caution`. A test at each end
  asserts `Control` in Swift and `deliver.CONTROLS` in Python agree.
- `e7e2eb7` read back through a transcript instead of only its tail: `page_turns(session_id,
  limit, before)` walks backwards and `before` counts from the end, so new turns never move an
  older page's boundary. 25 turns first, an "Earlier" control, and a scroll to index `added` so
  the reader stays put.
- `a1209e1` the briefing page settles — `Prose`'s trailing gap removed everywhere, the folder in
  the subtitle only when it is news, "4 OF 9 DONE" on the ask label, and the project's settings
  page reachable from the session's own controls menu.
- `d89840d` **the CLAUDE.md tree under Files** — the same tree `atlas tree` draws, reimplemented
  rather than shelled out to (atlas prints ascii and has no machine-readable mode), with the token
  estimate copied from atlas so the two never disagree. The tree is also a second permission door
  beside the transcript's path list. `Context` → `ContextDocs`, per the naming trap in
  `.claude/rules`.
- `9f514b3` **the tab bar is gone** — the panes are a paging TabView, the indicator is four
  non-interactive dots on the meter row, and edge-swipe-to-dismiss fires only on the first pane.
- `8ae7b54` the header is stripped to a name and a menu, with everything true of the session on
  the row beneath; the chevron goes because the panes are swiped now, and the way out stays named
  in the menu for VoiceOver. The pane's name slides in after a swipe and leaves — it must never
  become permanent, or it is the tab bar again.
- `d5bcc7d` panes run to the bottom of the screen; the things you press stay inside the safe area.
- `ead207b` panes are masked with 20pt of fade at the top and 12 at the bottom, and the mark leans
  back down into the safe area.
- `767bdcf` **thinking blocks** — 326 of them in one session, a quarter of a megabyte the phone
  could never see. Collected exactly as tool calls are, closed behind one line saying how many.
  Measured before choosing to carry them with the turns: median 548 characters, p90 1718, 18 KB
  for a real 25-turn page. `redacted_thinking` is skipped on purpose.

### The rail and the accent

- `8f71dd7` a rail row recedes as its session goes quiet — one opacity over the whole row, applied
  last, logarithmic, floored at 0.5. A busy session never fades whatever its stamp says, because
  `updated_at` is the moment the status last changed, not a heartbeat.
- `ec4b5b3` inline code takes the size of the sentence it sits in, less half a point. Three sizes
  on the page, named in one place. Also excludes `.worktrees/` from SwiftLint, where parallel
  agents had a second copy of every file.
- `92da498` **the accent is the screen's, not a control's** — read from the environment, set once
  per recording screen, so a view written next month gets it by writing `@Environment(\.accent)`
  rather than opting out by reaching for `Palette.tint`. Cannot stick orange: it is derived from
  the recorder's flag on every render. Also moves the filter chain onto the session's own menu, and
  stops disabling the whole controls menu when iTerm is down.
- `5df974b` the places the accent did not reach: the Files tab's glyphs, and inline code and
  addresses everywhere prose is rendered. `AttributedString` is built outside the view tree, so the
  colour is a parameter there. Sheets stay teal — the page that is listening is the one that changes.
- `2c154fe` the Say mark matches the 17pt plain words it shares a sheet with.
- `4e8b8a0` a todo box is one square, filled by how far it got (following `5d4c603`'s move from
  dots to boxes).

### Prompts, briefings and the summariser

- `11ac74a`, `bb0e7a5` checkpoint and then clarify the crafting filter's rewriting rules.
- `fb7e97c` checkpoint of `sessions.py` and `summarize.py` — **this one broke `develop`**: it
  landed `last_request()` while `app.py` still called the `context_used()` it replaced, so
  `GET /sessions` raised AttributeError on every request. Repaired at `8df2039`.
- `3cabf3a` make the briefing instructions explicit for Haiku.
- `8ad45a8` an **empty commit** — "checkpoint before Haiku configuration review", no files.
- `33386d1` configure the summariser for Haiku 4.5.
- `cfa2206` frame the summariser's user prompt in named tags.
- `b1e85d0` **every prompt becomes a file** under `prompts/` — briefing, crafting, idle-check —
  with a loader and tests, and the transcript test modules move under `tests/reading/`.
- `5ece032` the idle check names the session it is about, so a misrouted nudge is visible.
- `97de405` `docs/prompt-review.md`: a standing audit of every instruction a model can read here,
  with a five-step rollout order.

### Projects

- `ea01ddf` **start a session in any folder from the phone.** Three sources read in order, first
  to answer wins — the person's `projects.json`, atlas over HTTP, atlas's scan cache — with the
  source travelling with the list so a stale list says so. Three things measured rather than
  assumed: `it2 tab new` makes a pane whose shell never reads input (a daemon has no current
  window), bare `claude` opens the dashboard and writes no session record (`--name` is what starts
  one, and it is not in `--help`), and an untrusted folder stops at a question only somebody at the
  Mac can answer, so it is refused up front. 2.7s from tap to a session with a pane.
- `89692d9` those four discoveries written down, plus the `StubProtocol` trap where two suites
  stubbing one transport answer each other's requests.
- `6dc8b82` hand back a started session with its pane filled in — the pane map is cached for three
  seconds, so a window opened two seconds ago reported `pane: null` in the one receipt that gets
  shown.
- `efab5f0` say more about a project than its name: framework, runner, branch, dirty tree, port,
  open issues and domains, all of which atlas already knew and the daemon was discarding. Search
  matches on every one. Not carried: libraries — atlas discards the dependency list after
  classifying. 465 projects, 169 KB.
- `3298cc6` **switches for the things this Mac does without being asked** — the Lock Screen card, the
  idle check, and two new ones: a card when a slip goes unanswered, and one an agent raises for
  itself (`POST /sessions/{id}/notify`). Keyed by path, not session id, because an id dies on
  restart. Overrides are per key. Also which model a session starts on and which writes briefings.
  States plainly that the app side is not built yet.
- `ad29471` the app side: long-press a project for its page — switches, models, and the sessions
  running in it with Compact and End beside each. Decoded with no key strategy for a sharper reason
  than filters had: the keys of `projects` are folder paths, so `convertFromSnakeCase` would rename
  `/dev/_sandbox/my_thing` and lose its override.
- `e047220` the same switches on the app's own settings screen — until this, every folder could
  override an answer that had no way of being set globally. Written straight through, because the
  Mac answers with what it stored, which is not always what was sent.
- `74215cb` say which model each picker on a project's page is for; both rows read "Default".

### Mermaid

- `0312c54` a ```mermaid fence draws as a diagram. mermaid is bundled (11.12.3, MIT, 2.8 MB) and
  injected as a `WKUserScript` on the same host-initiated lane the slip bridge uses, so it works
  with the Mac asleep and the artifact policy did not move. A surface that sets no renderer shows
  the source, so a diagram can never be why a transcript has a hole in it. Also corrects the root
  wire list, which claimed a `PUT /filters` that `002dea1` had removed.
- `7265ad0` **fix of the above**: the renderer went into `Markdown`, and a transcript does not use
  it — a turn is drawn as the words the session said with nothing else interpreted. `Fenced.parts`
  lifts the fence out of the words instead; a ```swift block keeps its backticks, and an
  unterminated fence stays words.

### utt, the daemon, and the rest

- `f28f614` the Files tab took 1.5s because of one regex: `.` inside a greedy prefix as well as
  after it, so the engine backtracks through every path-shaped blob. Finding runs first is linear —
  1.38s → 0.14s on a 41 MB transcript, same 351 matches, diffed rather than assumed. Opening a file
  paid it twice, because `allowed()` runs the same scan.
- `8df2039` the week and the model in the overview footer, both riding the listing the phone
  already fetches. The week comes out of the statusline agent's own cache, is not clamped past
  100%, and cuts days rather than rounding. Repairs `fb7e97c`. A real bug fell out of the same
  scan: a `<synthetic>` entry carries a usage dict of zeros, so stopping at one reported an empty
  context window and named `<synthetic>` as the model.
- `2d4f5b6` follow utt's rename of `plugins` to `extensions` — **corrected at `d393027`**, because
  the hazard was never the new name: the *installed* build decides which folder exists, and
  `transcribe` returns early on a missing jobs folder, so hold-to-talk dies with nothing in the log.
  `plugins_dir` asks the disk, newest name first. The rename also reset JJ's own utt attribution to
  the default and left a window with no jobs folder at all.
- `a882a86` two silent things from an audit of utt's source: the manifest never declared
  `skipsTextStages`, so every prompt went through whatever this Mac's utt text pipeline is set to —
  `formatting` lowercases and strips punctuation, which is the payload for a coding prompt.
  `cleanup` and `replacements` are kept deliberately. Second: utt services a jobs folder only while
  the extension is enabled, so switching Deckhand off left clips unread and hold-to-talk blocking
  for three minutes; the marker file is now one stat.
- `35b5b0c` corrects three things in this repo that stopped being true, including `saying.py`'s
  claim that its transcript is "what utt heard": the jobs answer carries no raw text, so utt's
  cleanup stage and any other extension declaring `filtersTranscripts` have already run.
  `skipsTextStages` bounds utt's own stages and nothing bounds the others — written down, because
  there is nothing on this side to fix it with.
- `444ac67` the expanded Dynamic Island fits its own content: a `Text` draws into the height it is
  offered and clips the rest, so `fixedSize` is the ask.
- `7ce3f99` `just device` was installing to the *other* phone — an iPhone 12 Pro deliberately
  behind on builds — reporting "App installed" and exiting 0. The Pages tab was missing on the 17
  Pro for that reason and no other.
- `a3330c2` SwiftLint excludes agent worktrees under `.claude` too.

### Docs

- `82a2e18` **root CLAUDE.md becomes a map and nine context packets**, GLOSSARY.md is new, and two
  cross-cutting rules move to `.claude/rules/` (Swift naming traps, the agent journal protocol).
  554 lines and ~18k tokens at every session start, of which 372 lines were a Quirks section every
  session paid for. Nothing dropped; quirks kept verbatim where the wording carried a measurement.
  Answers item 3 of `docs/prompt-review.md`.
- `5e60907` **fix of the above**: it put a CLAUDE.md under the app target's source root beside the
  one in `Views/Annotation/`, and XcodeGen flattens every unhandled file into the bundle — both
  became `Deckhand.app/CLAUDE.md` and the build failed with "Multiple commands produce".
- `393b28b` two traps that have each cost a build: the two-letter name the lint refuses, and
  SwiftUI state set inside `updateUIView` being dropped silently (the bug `fed6643` shipped).
- `ce7dbb4` the slash-command lane, and why it needs a pane.
- `420d9d0` `docs/control-surface.md` — what driving the whole app from a command interface would
  take, and what such a surface must refuse.
- `6e4e7a0` `docs/agent-surface.md` — what an agent *inside* a session needs to know about
  Deckhand, and why that is a skill rather than an MCP server: the most valuable part needs no tool
  at all, because a slip is a file the agent writes in its own cwd. The MCP surface is designed in
  full and phased fourth. Two things carried out of it: `CLAUDE_CODE_SESSION_ID` is injected into
  every Bash call and equals the registry's sessionId, and the refusals a tool surface would
  declare are a default rather than a fence while the agent keeps Bash and the pairing token is a
  readable file.

### Clips kept on the phone

- `dd3f81f` a clip lived in the temporary directory until its upload succeeded, and the upload ran
  inside `run`, which swallows a throw — a sleeping Mac, a refused token or a timeout left the file
  orphaned and the words nowhere. `ClipArchive` files a clip before it goes on the wire, with an
  atomic index carrying the transcript, whether it went, and why not. Nothing in the app deletes a
  clip; the sweep drops only what reached a session, after seven days.
- `be31399` **merge** of the clips branch, adding the third instance of the same swallowed-throw
  shape in the dictation path (fixed with a `defer`; dictation clips are deliberately not archived,
  since those words go into a field the person is watching).
- `0103784` **fix of the above, and the last commit on the branch.** The archive gesture went on as
  a second ViewModifier wrapping the talking one, which put its long press *outside* the tap — so
  in tap-to-talk the tap never arrived and the button simply stopped recording. One modifier now,
  so the order cannot drift. Also removes the standing "· HOLD FOR CLIPS" label: a line of
  instruction on screen every second the app is open, to explain a thing you do once.

---

## Directions taken back

The lines above mark these in place; collected here because they are the ones worth knowing.

| Added | Taken back | What happened |
|---|---|---|
| `b60579b` menu bar app | `781c153` | Its four buttons became three actions on Deckhand's page inside utt plus utt's own Restart. `276c271` deliberately did **not** carry over "Stop listening", because `bootout` cannot be undone by `kickstart`. |
| `2c782be` socket as the way in | `d05e2b4` | Replaced by the keyboard route; socket kept as the fallback, then made an explicit choice at `8208f5e` and refused for slash commands at `5869b9e`. |
| `804a21f` utt HTTP API + 1Password token | `6ecd850` | The file lane deleted the token, `UTT_SECRET`, `just sync-secrets` and the 401 fallback added at `a5da96e`. Docs corrected at `7f39574`. |
| `bd4aa2f` no auto-scroll on first load | `6e61537` | Deliberate, to save the summary card at the top of the transcript — obsolete the moment `f2a71b6` gave the briefing its own tab. |
| `825bf78` grey optimistic copy | `3f7738c` | Its comparison was fixed at `6e61537`, then the whole thing removed: it read as "not sent yet", the opposite of what it meant. |
| `f6a7c2f` tab order Summary/Files/Transcript/Pages | `7da0397` | Reordered one minute later; the tab bar itself removed at `9f514b3`. |
| `5d4c603` ask marks as boxes | `4e8b8a0` | Boxes replaced dots, then became one square filled by progress. |
| `37d2667` one global chain, `PUT /filters` | `002dea1` | Chains became per terminal; the old global file was renamed rather than copied out. The root wire doc still advertised `PUT /filters` until `0312c54`. |
| `c7ec08c` dismiss-the-callout-on-tap | `bd5ab25` | The platform idiom, wrong here: single tap waits for double tap to fail, so it would have zoomed. |
| `a1f42da` files grouped by suffix | — | Shipped with JJ's objection recorded in the same commit; the selector control is what `5d20fe4` and `f6a7c2f` then reused. |
| `2d4f5b6` hard-name `extensions/` | `d393027` | Only the disk knows which folder the installed utt made. |
| `0312c54` mermaid in `Markdown` | `7265ad0` | A transcript does not use `Markdown`; the fence is lifted out of the words instead. |
| `dd3f81f` archive gesture + "HOLD FOR CLIPS" | `0103784` | The gesture broke tap-to-talk outright; the label was noise in an app where nothing is labelled at rest. |
| `fb7e97c` `last_request()` checkpoint | `8df2039` | Left `app.py` calling a method that no longer existed — `GET /sessions` raised on every request in between. |
| `82a2e18` CLAUDE.md under the app source root | `5e60907` | Two CLAUDE.md flattened to one path in the bundle and the build failed outright. |
| `38908eb` bundle id left as `com.jj.Deckhand` | `57c2e5a` | Deferred as "not free", then forced: push cannot be enabled on a wildcard App ID. |

Two more worth naming, neither a revert: `a601ff9` renamed `ok` → `succeeded` on both sides of the
wire in one commit, and `8ad45a8` is an empty commit.

---

## Still open / known gaps

Sourced from the commit messages and checked against the tree on 2026-09-10.

**Repo state**

- `main` is at `7b260ed` (the scaffold), 142 commits behind `develop`. No tags, no releases.
- The working tree is dirty and being edited by a concurrent session as this was written
  (15:47): `.quality.json`, `Justfile`, `daemon/src/deckhand_daemon/log.py`, `saying.py`,
  `transcribe.py`, `prompts/idle-check.md` and `daemon/tests/test_nudge.py` — item 2 of the
  prompt review, in progress. Re-check `git status` before trusting this line.
- Untracked and uncommitted: `skills/deckhand/` (`SKILL.md`, scripts `answer.py` and `slip.py`,
  reference `wire.md` and `traps.md`, templates symlinked to `demos/`) and
  `daemon/tests/test_skill_scripts.py` — phase 1 of `docs/agent-surface.md`, not yet committed.
- Two linked worktrees are still checked out and locked under `.claude/worktrees/`
  (`agent-a93ad06cb63c23d46` at `6c20d19`, `agent-ae5565862889482f8` at `0103784`), and five
  `worktree-agent-*` branches remain, three of them with no worktree left.

**Named as not built, in the commit that noticed**

- No control on the phone creates a second copy of a filter in a chain; duplicates round-trip and
  edit correctly (`efa638e`).
- Slips get no mermaid — an artifact page is sandboxed by its own CSP and nothing injects it
  (`0312c54`).
- The MCP surface in `docs/agent-surface.md` is designed and phased fourth, not built; making an
  agent's refusals real needs a second token, the same one `docs/control-surface.md`'s last phase
  needs (`6e4e7a0`, `420d9d0`).
- `_http._tcp` is still in `NSBonjourServices` beside the `_deckhand._tcp` the pairing screen
  now actually browses. Nothing in the app browses it — there is no `NWBrowser` outside
  `Finding/Beacon.swift` — and Apple's local network privacy note puts `.local` *name*
  resolution under `NSLocalNetworkUsageDescription` rather than under this list, so it should
  be removable; it is kept because that has still never been tested on a device and the thing
  it would break is the app's only working address (`38908eb`).
- `test_a_clip_becomes_text` polls a wall clock and loses under heavy parallel load; still at
  `daemon/tests/test_transcribe.py:44`, still deadline-based rather than event-based (`41cddfb`).
- Nothing bounds what *other* utt extensions do to a transcript before Deckhand sees it;
  `skipsTextStages` bounds only utt's own stages (`35b5b0c`, `a882a86`).
- "Which libraries does this project use" has no answer anywhere on this Mac — atlas discards the
  dependency list after classifying (`efab5f0`).
- Two things are blocked by the iOS 18 floor: an item in WebKit's edit menu (`UIContextMenuSystem`
  is iOS 26) and inserting dictated words at the caret (`TextSelection` is iOS 26) — `c1b167d`,
  `bc971f5`.

**`docs/prompt-review.md` rollout**

Item 3 (the CLAUDE.md / rules split) was answered by `82a2e18`. The doc's other four steps are
open as written: SessionStart hook messages and their tests; the crafting and idle-check contracts
plus behaviour cases; prompt loader contracts and briefing evidence serialised as data; and a live
evaluation baseline before any prompt simplification or model comparison. Its own P0 list still
names both SessionStart hooks and `crafting.md`'s skill-reference contract.
