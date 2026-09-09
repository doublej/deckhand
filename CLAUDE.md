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
- Summaries: the Claude Agent SDK, sonnet at low effort, one turn, no tools.
- The Mac-side UI is Deckhand's page inside utt (`plugin.py`): three settings, and buttons for
  stop, copy the pairing code and open the log. Start and restart are utt's own Restart button,
  which reads live launchd state from `daemon.label`. There was a menu bar app for this; the
  plugin page replaced every reason it existed, so it is gone.
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
  StatePill.swift # the four-letter state vocabulary, and a glyph on its tile
  Chrome.swift    # Card, SettingsGroup, SettingRow, PageHeader
daemon/src/deckhand_daemon/
  sessions.py     # which Claude sessions are alive, and their iTerm pane
  transcripts.py  # the last rounds, and the activity blob a summary is written from
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
`POST /sessions/{id}/focus` brings that pane forward on the Mac. `/health` is the only
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
