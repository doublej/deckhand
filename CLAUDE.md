# deckhand

> iOS remote for the Claude Code sessions running in iTerm on the Mac

## What this is

Two halves in one repo. A Python daemon on the Mac lists every live Claude Code session,
serves the last rounds of its conversation, and stores voice clips the phone sends. A SwiftUI
iOS app is the remote: pick a session, read what it just said, hold to talk.

What is shipped, end to end: the phone lists sessions, reads the last rounds, and holds to
talk; the Mac stores the clip, transcribes it with utt, and writes the text straight into that
session's own inbox socket, the way one Claude session messages another. The daemon is
controlled from its own page inside utt.

## Stack

- Daemon: Python 3.13, FastAPI, uv. Port **4180**, binds `0.0.0.0`, launchd agent
  `com.jurrejan.deckhand`. Logs to `~/Library/Logs/Deckhand/deckhand.log`, which is what
  Console.app shows in its sidebar (`just logs` to follow it).
- Transcription: utt, on-device, over the **plugin file lane** — the clip is written into
  `~/Library/Application Support/dev.jurrejan.utt/plugins/deckhand.jobs/` and utt writes the
  text beside it. No listener, no token, nothing on the network, and it works whether or not
  utt's HTTP API is switched on. `plugins/deckhand.json` is the manifest, rewritten at every
  start-up; `deckhand.values.json` carries what the person set on the page, and
  `deckhand.action.json` which button they pressed.
- Summaries: the Claude Agent SDK, sonnet at low effort, with the three task tools and nothing
  else. One run writes both the briefing and the person's list. The daemon owns the schedule:
  briefings are files, one worker walks the sessions, and the phone only ever reads. `/summary`
  reports what it spent; a run bills a few hundred tokens against fifty thousand read from
  Anthropic's prompt cache, so the two are counted apart.
- Lock Screen: a Live Activity (`widgets/`, target `DeckhandWidgets`) saying how many sessions
  have stopped and are waiting. The **Mac** drives it over APNs — a backgrounded app has no
  promise of running again — so the phone only hands over push tokens and the daemon does the
  sending (`push.py`). Bundle id is `dev.jurrejan.deckhand`, and it had to become explicit:
  push cannot be enabled on a wildcard App ID.
- The Mac-side UI is Deckhand's page inside utt (`plugin.py`): three settings, and buttons for
  copy the pairing code and open the log. Start and restart are utt's own Restart button, which
  reads live launchd state from `daemon.label`. `showsInMenuBar` puts the same status lines,
  the same Restart and the same buttons in utt's menu bar under a teal sailboat, so the tray is
  back without Deckhand shipping a status item of its own. There was a menu bar app for all of
  this; the plugin page replaced every reason it existed, so it is gone.
- App: Swift 6.2, SwiftUI, iOS 18. `DeckhandKit` (SwiftPM library) holds the models, the HTTP
  client and the design layer so they are testable on the Mac; the app target comes from
  XcodeGen.
- Look: utt's language, because Deckhand is a plugin of utt's and a guest borrows its host's
  identity whole. `Sources/DeckhandKit/Design/` is a port of `swift/utt/Utt/Design/` — the
  values are copied from there, never re-picked, so a change in utt is a diff here and not a
  redesign. The one thing that is Deckhand's own is `Palette.tint` (#3EAFB4) and its mark, an
  anchor on the same 6×6 dot grid utt's own mark lives on. Recording is the single exception:
  it goes utt orange, because recording is utt's job in every plugin. The hold-to-talk mark
  runs `DotMatrixDriver`, utt's shared clock, so it is never still: six seconds a pattern in
  silence, down to a tenth of a second at full voice, and the glow follows the phone's own
  input meter while you hold it.
- The app icon is the anchor on the same grid, drawn by `Sources/IconMaker` from
  `DotMatrix.rect` itself — `just icon` redraws it. Same geometry as the in-app mark by
  construction, so the home screen and the rail cannot drift apart. It sits at 0.74 of the
  canvas rather than the 0.62 a tile uses, because iOS masks the icon to a squircle.
- State on the Mac: `~/Library/Application Support/Deckhand/` — `token` and `audio/<sessionId>/`.

## Mental model

```
Sources/DeckhandKit/Design/
  Palette, Typography, Spacing   # utt's tokens, copied
  DotMatrix.swift # the 6x6 geometry and the level curves; DotGlyph holds the shapes
  DotMark.swift   # a shape on the grid, and the wordmark
  StateWord.swift # the four-letter state vocabulary, and a glyph on its tile
  Links.swift     # addresses in what a session wrote, and what localhost means from a phone
  Fade.swift      # how present a rail row is, given how long its session has been quiet
  Chrome.swift    # Card, SettingsGroup, SettingRow, PageHeader
daemon/src/deckhand_daemon/
  sessions.py     # which Claude sessions are alive, and their iTerm pane
  reading/        # everything that reads a transcript and nothing that writes one
    transcripts.py  # the last rounds, and the activity blob a summary is written from
    asked.py        # what the person asked for, and what is still in the session's inbox
    readable.py     # the whole transcript as lines, for when the app's reading looks wrong
  filters/        # what happens to a prompt between the phone and the session
    kinds.py        # Prompt, Verdict, Outcome, Field, Filter — the contract, and only that
    registry.py     # a filter declares itself here; known() describes them for the phone
    config.py       # the saved chain, where list order is run order
    runner.py       # runs it, and survives a filter that does not
    routes.py       # GET and PUT /filters, knowing nothing about tokens
    words.py        # the first filter: swap words dictation keeps getting wrong
  briefings.py    # where briefings are kept, and the one worker that keeps them current
  nudge.py        # asks a session that stopped about the asks still open on its list
  tasks.py        # the person's list of asks, and the only three tools that may change it
  files.py        # what the session touched that a person could open, and the permission
  push.py         # what the Lock Screen says, when it changes, and how it gets there
  transcribe.py   # utt turns a clip into text, through its jobs folder
  plugin.py       # Deckhand's page inside utt: the manifest, its settings, its buttons
  deliver.py      # the text goes into the session's own peer socket
  summarize.py    # what happened since you last spoke, via the Claude Agent SDK
  app.py          # the endpoints
  config.py       # data dir, token, port
  log.py          # the one log file, in ~/Library/Logs
Sources/DeckhandKit/
  Models.swift, DeckhandClient.swift, ServerSettings.swift
deckhand/         # the app: App, Model, Recorder, Views/
UITests/          # drives the simulator against a running daemon
launchd/          # the agent plist, symlinked into ~/Library/LaunchAgents
```

`GET /sessions` → tap a row → `GET /sessions/{id}/turns` and `GET /sessions/{id}/summary` →
hold to talk → `POST /sessions/{id}/audio`, which answers with the transcript and whether it
reached the session. `?deliver=false` transcribes without sending, for the review card, and
`POST /sessions/{id}/say` sends the text once the person has read it.
`GET /briefings` hands back every live session's last briefing at once, off disk, for a cold start.
`GET /sessions/{id}/raw` hands back the transcript as readable lines — one per event, the syntax
dropped — for when the question is whether the app read it right.
`POST /sessions/{id}/queue/clear` draws a line under an inbox holding prompts nothing will read.
`GET /filters` says what this Mac can do to a prompt and what it is currently doing; `PUT /filters`
replaces the chain. `GET /sessions/{id}/files` lists what the session touched that a phone can open and
`GET /sessions/{id}/file?path=` serves one. `POST /sessions/{id}/focus` brings that pane
forward on the Mac. `/health` is the only
unauthenticated route; everything else needs the `x-deckhand-token` header, and both
`/health` and `/sessions` carry an `iterm` field saying whether pane data is trustworthy.

## Quirks worth knowing

- **The join that makes this work**: Claude Code writes `~/.claude/sessions/<pid>.json` for
  every running session — sessionId, cwd, name, and a live busy/idle status. Those files
  outlive the process, so a record only counts when `ps` still shows that pid. `ps` gives the
  tty, `it2 session list --json` maps tty → iTerm pane. No hooks, no polling of iTerm's title.
- Transcript folder names are lossy (`/` and `_` both become `-`), so the JSONL is found by
  globbing `~/.claude/projects/*/<sessionId>.jsonl`, never by rebuilding the path.
- Transcripts run to megabytes: only the last 512 KB is read, and the first line of that
  chunk is dropped as a fragment.
- The **first** connection from a new client makes iTerm2 ask for Python API approval. Until
  someone clicks it, `it2` blocks: pane data is missing and `/sessions` costs the 4 s timeout.
  It happened once when the launchd agent was first bootstrapped and has been approved since.
  The pane map is cached for 3 s because one `it2` call costs ~0.5 s.
- **The iTerm join under launchd was a throttling problem, not an approval one.** The plist
  said `ProcessType: Background`, which puts the job in launchd's slow lane for CPU and I/O, and
  a lookup that costs ~1 s from a terminal then blew a 4 s timeout every time. It reads
  `Interactive` now, the timeout is 12 s, and panes resolve under launchd. A failed lookup still
  backs off for a minute so a real outage cannot starve the event loop, and the `iterm` field
  still says what is wrong. This matters for more than window titles: without a pane there is no
  keyboard, and delivery falls back to the peer socket.
- **A message absorbed mid-turn is a `queued_command` attachment, not a `user` entry.** It is
  true that no `user` entry is ever written for one — but it is written down, as
  `{"type":"attachment","attachment":{"type":"queued_command","prompt":…}}` at the moment it
  arrived, which is the entry Claude Code renders as "The user sent a new message while you were
  working". Measured on a live transcript: 149 of them, and **not one** also present as a user
  entry, so `transcripts.absorbed` can read them as turns with no risk of showing anything twice.
  Missing that is what made those messages look lost: `asked.queued` kept its own copy marked
  `taken` and the phone drew them after the last turn, so three answered prompts sat at the foot
  of the conversation looking like three nobody had got to. They are ordinary turns now, in the
  place they arrived, and `asked.queued` returns only what is still in the inbox. There is still
  no way to make a session read its inbox early — the queue drains when a turn ends — so the
  phone's "force" is Escape, and the button says "Stop the run so it reads this".
- **An inbox can hold prompts nothing will ever remove**: a session killed mid-queue leaves
  enqueues with no matching removal, and a replay cannot tell that from a message still waiting.
  `POST /sessions/{id}/queue/clear` writes a timestamp to `queue/<sessionId>.json` and the replay
  starts after it. Claude Code's transcript is never touched — it is not this daemon's file.
- **A briefing is a file, and the daemon decides when one is owed.** This was a dict in memory
  with a two-minute TTL, which cost more than everything else in Deckhand put together: a session
  that had done nothing since its last briefing still bought a model run every two minutes for as
  long as anyone had the list on screen — the activity hash made a re-read free only *inside* the
  TTL, and past it an unchanged transcript was a miss like any other. Nothing survived a restart
  either, so a reinstalled app faced a rail of blank rows and paid for every one again.
  `briefings.py` keeps the last one under `briefings/<sessionId>.json` and one worker walks the
  live sessions. Two gates before a model is touched, cheapest first: the transcript's own mtime
  (a session nobody has touched answers in a `stat`), then the activity hash (Claude Code appends
  plenty — a mode change, an attachment — that nobody wants a briefing about). Reading
  `/sessions/{id}/summary` never waits for a model: it answers off disk and **bumps** that session
  to the front of the queue, so opening a project is what promotes it. `GET /briefings` hands back
  every live session's last briefing in one call, which is what makes a cold start whole.
- **The idle check messages sessions on its own** (`nudge.py`). A session that has been quiet for
  `SETTLE` with anything unfinished on its task list is asked, over the **socket** route so it
  arrives labelled as another agent rather than as JJ typing, either to finish or to say why not.
  Two guards against a daemon that will not let a session stop: the same list is never asked about
  twice (fingerprint of ids and states), and never more often than `AGAIN` whatever the list does.
  `DECKHAND_NUDGE=0` turns it off.
- **The keyboard route's ctrl-U travels with the message.** Queued content written by Deckhand
  starts with `\x15`, so `asked._unwrap` strips control characters as well as the envelope tags.
- **The session's inbox is a lane of its own.** Claude Code writes a `queue-operation` line
  (`enqueue` / `dequeue` / `remove` / `popAll`) every time something joins or leaves a session's
  message queue, and `asked.queued` replays it. This is the only honest answer to "has it seen
  what I said yet": a message sent mid-turn is **not a turn** — it appears nowhere in the
  transcript until the session absorbs it, which is why speaking to a busy session and seeing
  nothing happen used to read as having sent nothing. `dequeue` carries no content, so the
  replay pops the oldest; a `remove` naming something outside the tail window does the same,
  which is what lets a replay that began mid-queue still empty in the right order.
- **How full a session's context is comes off its own transcript.** Every assistant entry
  carries the usage of the request that produced it, and the window is what was billed as
  input — `input_tokens` + `cache_creation_input_tokens` + `cache_read_input_tokens`. Output is
  not in it. The limit is `autoCompactWindow` from `~/.claude/settings.json` (450k here), not
  the model's own ceiling: what matters is when *this* Mac folds a session into a summary.
  Read over a 256 KB tail, because it is asked for every session on every listing. It lags by
  a turn on a busy session — the usage of a request in flight is not written until the assistant
  entry it produced lands — and it will not match a statusline counting against the model's full
  window rather than this setting.
- **The task list is the Mac's, not the model's.** It lives in
  `~/Library/Application Support/Deckhand/tasks/<sessionId>.json` and the summariser changes it
  only through three in-process SDK tools (`add_task`, `set_task_state`, `drop_task`) bound to one
  session's file. Written as part of the briefing it was a *new* list every run, which is how the
  shape of it kept changing. The model is handed the list with its ids and may not reword,
  renumber or re-order it; `drop_task` needs a reason and warns, because it is the only operation
  that loses something. Trimming is not the agent's job either: `MAX_KEPT` is a ceiling on a file
  and the phone decides how many to show (`AskList.shown`). This needs more than one turn, so the
  run is `max_turns=16` with `permission_mode="bypassPermissions"` — safe only because those three
  functions are the entire tool surface and nobody is at the daemon to answer a prompt.
- **A picture reaches a session as a path, not as a paste.** `POST /sessions/{id}/image` keeps
  the bytes under `images/<sessionId>/` and answers with the path; `POST .../say` takes
  `images: [path]` and `deliver.with_images` appends them to the words, so the session sees the
  file with its own `Read`. Terminal paste handling is not reachable from a phone and encoding an
  image into a typed prompt is not a thing, so the file is the mechanism. `app._kept_images` only
  passes paths inside that session's own folder — without it, "say this and read that file" would
  aim a session at anything on the Mac. The files are kept after delivery (the session may read
  one later, or twice); nothing prunes them yet.
- **`PhotosPicker` needs no usage description** and `UIPasteboard.hasImages` needs no permission,
  which is why the clipboard button only appears when there is something to paste: asking
  `UIPasteboard.general.image` is what triggers the system's paste consent, and only then.
- **A raw JSONL line cannot be one unwrapped `Text`.** The first raw-transcript view was a single
  `Text` of the whole file inside a `ScrollView([.horizontal, .vertical])`. Unwrapped, a 10k-char
  line is tens of thousands of points wide, and past that CoreText renders **nothing** — a black
  screen, no error, no warning. It is one wrapped `Text` per line in a `LazyVStack` now, and it
  says how many lines arrived so that empty never looks like broken again.
- **A prompt is filtered on its way in, and the chain is an ordered list.** `filters/` sits between
  the phone and `deliver`: `run(Prompt) -> Outcome`, where each step is
  `{"filter": name, "on": bool, "settings": {}}` in `filters.json` and **the array order is the run
  order**. Nothing is keyed by name, because the same filter may appear twice with different
  settings — a step is a position in a list, not an entry in a table. A step missing `on` is on. A
  filter that raises is logged, noted as skipped, and the words carry on unchanged; only an
  explicit `Verdict.stop` ends the chain, and `PUT /filters` refuses a name this Mac does not have
  rather than saving a step the runner would step over, because a step that silently does nothing
  looks exactly like one that silently fails.
- **`delivered: true` is not the same as "it was said".** The daemon can answer `delivered: true`
  alongside a stop, so every screen asks `Delivery.went` — `delivered && stoppedBy == nil` — and
  never `delivered` alone. A stopped prompt goes back into the review card rather than only into
  the status line: the card is the one place words exist unsent and it is editable, which is the
  only useful answer to "a filter will not pass that". The status line names the filter by its
  *title*, not its wire name.
- **`convertFromSnakeCase` rewrites dictionary keys too, not only struct keys.** A filter taking a
  `max_words` setting would be handed back `maxWords`, a key it has never heard of, and the
  setting would silently vanish. So `filters()` and `saveFilters()` decode through a decoder with
  no key strategy while the rest of the client keeps the conversion. Nothing on the filters wire
  is snake case, so nothing is lost either way; a test asserts `max_words` survives a real call.
- **A filter's settings are saved on dismissal, not per change.** A text field changes per
  keystroke — the same thing that produced 40-odd revisions in four seconds on the Mac's own
  plugin page — so `onDisappear` covers both Done and a swipe-down, and a dirty flag means no PUT
  when nothing changed.
- **`updated_at` is the moment a session's status last changed, not a heartbeat.** Measured here: a
  session reporting `busy` with a 1553 s old stamp while it was mid-turn. So it is only the age of
  an *idle* session, which is what `Fade` reads it as — a busy row is never faded whatever its
  timestamp says, or the hardest-working row on the rail would be the faintest one. The fade is
  one opacity over the whole row, applied last so the tile and border travel with the words, log
  curve from a two-minute grace to a 0.5 floor at eight hours. Portrait only; `SessionRow` has no
  other caller.
- **No badges.** A state is the word alone — 9pt mono, tracked, in the state's colour, nothing
  around it. It was a dot and a label inside a bordered capsule, ported from utt, and that shape
  is not to appear in this app again: it reads as something you press, and each one sits beside
  something you actually can. `StateWord` is the only place a state is drawn.
- **An address a session wrote is a tap, and `localhost` is a question.** `Links` marks bare URLs
  with `NSDataDetector` in both a turn and the summary's prose, leaving anything markdown already
  linked alone. A local host has no meaning on a phone, so `LocalLinks` intercepts the tap and
  offers the Mac instead — the address it reports for itself (`/health`'s `lan`, found by asking a
  never-connected UDP socket which interface would carry a packet out) and the one this phone is
  already reaching it on. Both, because neither is reliably the right one.
- **The talk control is a mark and nothing else.** It floats over the pane rather than sitting
  under it, and the scrolling panes add `TalkMark.clearance` to the end of their content so
  nothing is stuck behind it. No bar, no ground, no resting label: a band of furniture across
  the page to hold one button was the first thing asked to go. What a tap will do slides out on
  a pill to the left, the way out to the right, and both the mark and that left pill send —
  the pill reads as an instruction otherwise. Because it floats, `TalkControl` sets **no**
  `contentShape` of its own: the hit area is whatever the caller drew, or an invisible
  full-width slot would swallow taps meant for the page behind it. Nothing is labelled at rest,
  so the UI test looks for the mark's `talk-mark` identifier.
- **A gesture on a list row has to share the touch.** The sessions row has three jobs on one
  touch: tap to open, press to talk, swipe to star. `highPriorityGesture` and `ExclusiveGesture`
  both take the touch and broke the tap *and* the swipe; a `Button` takes it the other way and the
  press never fires; a `DragGesture` sequenced after the long press is read as the start of a
  swipe. What works is the plainest thing: not a `Button`, `.onLongPressGesture` for the press
  (with `onPressingChanged` for hold-to-talk's release, which is why there is no drag in it) and
  `.onTapGesture` for the tap, whose meaning `TalkControl.tapped` decides. `UITests` holds all
  three down, including that a press must not open the session.
- **Never call a public type `Context` in DeckhandKit.** Inside a `UIViewRepresentable`,
  `Context` is already a typealias for `UIViewRepresentableContext<Self>`, so a module-level
  `Context` imported beside SwiftUI silently breaks the conformance of anything spelling
  `makeUIView(context:)` the documented way — the error names the representable, not the clash.
  It is `ContextWindow`.
- **Renaming is `/rename`, Claude Code's own command**, typed into the pane like anything else
  — it is `supportsNonInteractive`, so with an argument it renames without opening a picker.
  Verified against a live session: the registry's `name` and `nameSince` both move. The phone's
  favourites and hidden set are keyed by **name**, so `Preferences.renamed(from:to:)` has to
  carry them or a starred session silently loses its star. A busy session only runs the command
  when its turn ends, so the listing catches up late and the app says so rather than lying.
- **Stop, compact and clear are keystrokes, not messages.** `deliver.control` sends Escape for
  a cancel and types `/compact` or `/clear` the same way a spoken line is typed. The peer socket
  cannot do any of them — it delivers a message and none of these is one — so a session with no
  iTerm pane cannot be controlled from the phone and the menu says so rather than failing
  quietly. `clear` is the only irreversible thing in the app and the phone confirms it.
- **Serving a file is not the same size as taking one.** `MAX_FILE_BYTES` is 512 MB against
  `MAX_UPLOAD_BYTES`'s 32 MB, and reusing the upload cap for `/file` is what made every video a
  session rendered come back as 413 — read on the phone as "cannot display this". The phone
  downloads to a temporary file rather than into memory, because AVPlayer wants a URL and a
  rendered clip is bigger than every voice clip ever recorded into that session put together.
- **The file listing is the whole permission.** `/file` serves a path only because that
  session's transcript named it, re-derived per request. There is no allow-list to maintain and
  no way to widen it by accident — which is what keeps a file endpoint off the rest of the Mac.
  Source files and `node_modules`/`.build`/`.git` are left out on purpose: the tool trace
  already shows the code, and a phone listing 200 files shows nothing.
- **A `NavigationLink` inside a `List` costs two things**: it draws the system's disclosure
  chevron outside the row's own fill, and it swallows `swipeActions` so a swipe never reveals
  them. The sessions list uses a plain `Button` and `navigationDestination(item:)` instead.
  The UI test caught the second one ("no star action on the row"); nothing catches the first.
- **Hiding the navigation bar takes swipe-back with it.** `SessionView` catches its own: a
  `simultaneousGesture` that only fires for a drag starting within 28pt of the leading edge,
  simultaneous so it never competes with scrolling the transcript.
- **The clip must be whole before it is audio.** utt picks up finished audio extensions from
  the jobs folder, so a clip is written as `<name>.wav.part` and only then renamed — skip the
  rename and utt reads the file mid-write. `<name>.hints.json` goes in *before* the rename, or
  it is a hints file utt has already run past. The extension has to match the bytes:
  AVFoundation picks its reader from the extension, so a wav named `.m4a` fails to open
  however correct it is. utt deletes the audio and the hints; the answer file is ours to remove.
- **Hints are the cheapest accuracy in the system.** Every clip was dictated at a named session
  working in a known folder, so the vocabulary is known before the clip is even recorded
  (`transcribe.hints_for`). utt only lets a hint displace text that is already nearly it and
  starts with the same letter, so the list cannot rewrite a sentence: it catches "cockwheel" →
  "cogwheel", "Tu Y" → "TUI", "deck hand" → "deckhand". It cannot fix an ordinary word misheard
  as another ordinary word ("previous tree" for "previous three" stays wrong).
- **The daemon no longer holds a token of utt's.** It used to read one from onenv, materialise
  it to a 0600 file for launchd, and fall back to utt's own `settings.json` on a 401. The file
  lane removed all three: `needsApi` is false, so utt hands out nothing and there is nothing to
  go stale. `just sync-secrets` is gone with it.
- **Every action has to be safe to press by accident**, because `showsInMenuBar` is all of them
  or none — there is no per-action opt-in. There was a "Stop listening" action running
  `launchctl bootout`, which *unloads* the job; utt's Restart is `kickstart`, which cannot revive
  a job that is not loaded (verified: exit 113, "Could not find service"). It was a one-way door
  with no handle on the far side, and utt 1.1.0 does not honour `confirms` from the menu, so it
  was one mis-click from the daemon being gone until someone opened a terminal. Stopping it for
  good is `just uninstall-agent`, which is the right place for that.
- **The Lock Screen card is push-to-start, never started by the app.** Asking for one at launch
  would park "Nothing waiting" on the Lock Screen for hours, which teaches you to ignore it. The
  app hands over a `start` token and the daemon raises a card the moment a session goes
  busy → idle; that transition is the only event here. A session already idle when the daemon
  starts is not one, or every restart would announce old news.
- **APNs needs a key the daemon cannot mint.** `just sync-apns` materialises `deckhand/APNS_KEY`
  and `APNS_KEY_ID` out of 1Password, for the same launchd reason as ever. The key itself is
  created by hand once in the developer portal (Keys → new key with APNs enabled). Without it
  everything works up to the send and the log says `no push key on this Mac`.
- **The APNs host must match the entitlement.** The app signs `aps-environment: development`, so
  the daemon talks to `api.sandbox.push.apple.com`; a token minted for one host is refused by the
  other. A TestFlight or App Store build flips both.
- **`attributes-type` in the push payload is the Swift type's bare name** (`Deck`). Nothing
  checks that the two still agree, so renaming the type in `LiveActivity.swift` silently breaks
  push-to-start until `push.py` moves with it. The `ContentState` field names are the wire
  format for the same reason — there is no Swift on the sending side.
- **The plugin page needs utt 1.1.0 or newer.** Before that, utt dropped manifest keys that
  were not all-lowercase and said nothing, so `copyToken` and `openLog` never became buttons and
  only `stop` did — a page can be half-missing and look complete. 1.1.0's `isSafeKey` accepts
  camelCase. There is still no way for a plugin to learn that a key was refused, so a button
  that does not appear is the only symptom.
- **A string setting arrives per keystroke.** `revision` is correct per write, but typing one
  sentence into the attribution field produced 40-odd revisions in four seconds. Anything done
  on a values change has to be cheap, or debounced. Reading a value and assigning it is cheap;
  restarting something would not be.
- Anything the summariser or the transcriber needs must be reachable without a person present.
  The summariser passes `setting_sources=[]` for the same reason it is fast: loading the user
  settings starts every configured MCP server, which cost more than a minute.
- Sessions with no iTerm pane are hidden — unless iTerm answers nothing at all, in which case
  every live session is listed so the app still works without the iTerm Python API.
- **A screen is one of two surfaces.** The sessions list and the landscape deck are the rail:
  `Palette.lcdGround` with `.environment(\.colorScheme, .dark)`, whatever the phone is set to.
  Everything else is a page on the system's own light ground. The app therefore forces no
  colour scheme — it did once, which made both surfaces the same and lost the distinction the
  whole language rests on.
- Session glyphs are derived from the session's name with FNV-1a, not `hashValue`: Swift seeds
  its hashing per process, so a session's face would change on every cold start.
- ATS: the app talks plain HTTP to a `.local` name, which needs `NSAllowsLocalNetworking`
  plus `NSLocalNetworkUsageDescription` (both in `project.yml`, not a checked-in plist).
- **Installing on a phone** (`just device`, `just phone="Pocketline Swing" device`) takes four
  things, and the error message names whichever is missing: Xcode signed in to the account for
  team KA6433FU8U; `-allowProvisioningDeviceRegistration` alongside
  `-allowProvisioningUpdates`, or a phone that is not already in the team's wildcard profile is
  refused with "isn't registered in your developer account"; an **unlocked** phone, or the
  developer disk image will not mount; and, the first time a phone gets a build from this team,
  the profile trusted by hand in Settings → General → VPN & Device Management. Deployment target
  is iOS 18.0 — the 12 Pro runs 18.7.
- `xcrun devicectl device process launch ... -- -deckhand.host <host> -deckhand.token <token>`
  starts the app already paired; the model writes launch-argument settings back to defaults, so
  the pairing survives a cold start. The `--` matters: devicectl eats the flags without it.
- **Reading it first is on by default.** Speaking into a busy session cannot be undone, so the
  transcript is held in a card — utt's own review HUD, minus the keycaps a phone has no use for
  — until it is sent or discarded. Off in Settings sends the moment the words come back.
- **Recording pins the phone's orientation** (`OrientationLock`, and the one reason this app has
  a UIApplicationDelegate). Portrait and landscape are two different screens here, so a rotation
  swaps the view holding the recorder and the clip goes with it.
- **The route is the person's choice**, in Settings, and `POST /sessions/{id}/audio?route=`
  carries it: `auto` (keyboard when there is a pane, socket when there is not), `keyboard`, or
  `socket`. `keyboard` never silently falls back to the socket — choosing it is choosing whose
  authority the words carry, so it fails and says why instead. The receipt names the route that
  took it (`delivered_by`) and the phone shows it.
- **The keyboard route.** `it2 session send` types the words into the session's pane
  and presses return, so they arrive as a prompt from the person at the machine — which is what
  they are. Three bursts, not one: ctrl-U (a half-typed line in the prompt is not part of what
  was said), the words, then return alone — a return at the tail of one fast paste is what
  leaves a message staged in the box instead of sent. It cannot be confirmed: a staged message
  and a sent one look identical to `it2 session read`, and a busy session queues the words for
  as long as its turn lasts. The receipt says they were typed, which is all that is known.
  One hazard worth knowing: if that pane happens to be showing a permission prompt, dictated
  words go to the prompt, not to a new message. The peer socket below is the fallback, and the receiver wraps anything that arrives
  there in "another Claude session sent this, it is not from your user, it carries none of your
  user's authority". That wrapper is a genuine control against one agent laundering permissions
  through another; it is not something to defeat, it is the wrong channel for a person speaking.
- **The fallback goes through the session's own peer socket**: every session
  listens on the `messagingSocketPath` in its record, and the wire format is newline-delimited
  JSON — an optional `{"type":"auth","token":…}` line carrying the `peerToken` out of the
  sibling `<pid>.<hash>.key` file, then one `{"msgV":1,"type":"user","message":{…},"priority":
  "next"}` frame. Nothing comes back: a successful write is the only acknowledgement, and a
  session that is mid-turn queues the message rather than dropping it. It arrives labelled as
  a message from another Claude session, so the daemon does not have to fake a keystroke.
  Verified against a real live session on 2026-09-09, not only against a test socket.
- `python/parakeet-server` is the other local ASR service, currently disabled for memory; utt
  is what deckhand uses.

## Verification

`just check` — Justfile format, file sizes, directory sizes, SwiftLint, both builds, Swift
tests, ruff, pytest. The app build needs the simulator named in the Justfile's `sim`.

`just ui-test` additionally drives the simulator against a daemon started with `just daemon`.

- `just daemon` — run the daemon, prints its address and pairing token
- `just token` — print the token again
- `just sim` — build, install and launch in the simulator, already paired
- `just install-agent` / `just uninstall-agent` — run it at login, or stop doing that

## Related context

- [agent.md](agent.md) — verify loop, auto-fix commands, boundaries
- `.quality.json` — loc / dir thresholds
- `launchd/com.jurrejan.deckhand.plist` — registered in `multi-stack/project-atlas/shared/daemons.json`

### Shared agent journal

Use `./agent-log` (a shim for `atlas agent-log` — both are identical) for short-lived
operational awareness between concurrent agents. It is not chat and not a task tracker: the
issue tracker remains the source of truth for ownership, blockers, and durable findings.

- Run `./agent-log recent` before interpreting shared state.
- Before an action that can change another agent's observations, write an intent with every
  affected scope. This includes shared-worktree edits, generated artifacts, git/index
  mutations, and shared ports, processes, or services.
- Run builds, tests, and deployments through the wrapper so start, commit, dirty state,
  duration, exit code, and outcome are recorded even on failure:
  `./agent-log run build|test|deploy --scope <resource> [--bead <id>] -- <command...>`.
- For manual operations, use `./agent-log begin <operation> --scope <resource> [--bead <id>]
  -- <summary>` and always close the returned id with `./agent-log end <id> --outcome
  ok|failed|cancelled -- <result>`. `<operation>` is one of build, commit, deploy, edit, implement, investigate, merge, push, review, sync, test — what
  makes this particular run specific goes in the summary, never in an invented operation name.
- Record a temporary result-affecting discovery with `./agent-log finding --scope <resource>
  --evidence <fact> [--bead <id>] -- <summary>`. This is the entry that saves another agent a
  wasted run, and the one most often skipped — write one whenever you learn something that
  would change what a concurrent agent does next, especially a dead end. Promote lasting
  knowledge to the issue tracker or the relevant doc.
- At session end, write `./agent-log handoff -- <stopping point + next step>` — the durable
  baton the next session's briefing picks up. Handoffs never expire; the latest one is
  always shown by `recent`.
- Intents expire after 20 minutes and findings after 4 hours unless `--ttl` overrides them.
  Renew by closing and reopening an intent; never treat an expired entry as current.
- Keep summaries factual and short. Do not reply, ask questions, mention agents, narrate
  routine progress, or log isolated reads/edits/tests that cannot affect anyone else.

Canonical scopes are `path:<repo-relative-path>`, `artifact:<name>`, `service:<name>`,
`host:<name>`, `port:<number>`, and `git:<worktree-or-ref>`; a repo may define additional
canonical scopes of its own. Add multiple `--scope` flags when needed. The journal SQLite db
lives in the git common directory, so linked worktrees share it without dirtying the repo.
