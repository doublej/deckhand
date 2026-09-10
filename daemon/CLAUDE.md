# The daemon

## What this is

The Mac half. A FastAPI service on port 4180 that lists every live Claude Code session,
serves the last rounds of its conversation, takes voice clips from the phone, and writes
the words back into that session. It runs as launchd agent `com.jurrejan.deckhand` and
logs to `~/Library/Logs/Deckhand/deckhand.log`.

State lives in `~/Library/Application Support/Deckhand/` — `token`, `audio/<sessionId>/`,
`images/<sessionId>/`, `tasks/<sessionId>.json`, `briefings/<sessionId>.json`,
`queue/<sessionId>.json`, `timings.jsonl`.

## Mental model

```
app.py          # the endpoints, and nothing else
config.py       # data dir, token, port
log.py          # the one log file, in ~/Library/Logs
sessions.py     # which Claude sessions are alive, and their iTerm pane
projects/       # what folders there are, and starting a session in one
reading/        # everything that reads a transcript and nothing that writes one
deliver.py      # the words go into the session, by keyboard or by socket
saying.py       # what a spoken line becomes before it is delivered
filters/        # what happens to a prompt between the phone and the session
projects/       # the folders on this Mac, and starting a session in one of them
prompts/        # every prompt this daemon sends a model, and nothing else
briefings.py    # where briefings are kept, and the one worker that keeps them current
summarize.py    # what happened since you last spoke, via the Claude Agent SDK
tasks.py        # the person's list of asks, and the only three tools that may change it
nudge.py        # asks a session that stopped about the asks still open on its list
files.py        # what the session touched that a person could open, and the permission
artifacts.py    # slips: what a session left for the phone to answer
transcribe.py   # utt turns a clip into text, through its jobs folder
plugin.py       # Deckhand's page inside utt: the manifest, its settings, its buttons
push.py         # what the Lock Screen says, when it changes, and how it gets there
```

Before editing under `reading/`, `filters/` or `prompts/`, read that folder's own CLAUDE.md.
`projects/` carries its own context in its `__init__.py` docstring — read that first; it is the
one lane that *makes* a session rather than speaking to one.

## The join that makes this work

Claude Code writes `~/.claude/sessions/<pid>.json` for every running session — sessionId,
cwd, name, and a live busy/idle status. Those files outlive the process, so a record only
counts when `ps` still shows that pid. `ps` gives the tty, `it2 session list --json` maps
tty → iTerm pane. No hooks, no polling of iTerm's title.

Sessions with no iTerm pane are hidden — unless iTerm answers nothing at all, in which case
every live session is listed so the app still works without the iTerm Python API. `/health`
and `/sessions` both carry an `iterm` field saying whether pane data is trustworthy.

- The **first** connection from a new client makes iTerm2 ask for Python API approval. Until
  someone clicks it, `it2` blocks: pane data is missing and `/sessions` costs the timeout.
  It happened once when the launchd agent was first bootstrapped and has been approved since.
  The pane map is cached for 3 s because one `it2` call costs ~0.5 s.
- **What utt may do to a Deckhand clip is declared, not inherited.** The manifest names
  `skipsTextStages: ["formatting"]`. A prompt on its way into a coding session is not dictation
  into a text field — the capitals, the punctuation and the exact words are the payload — and
  `formatting` is the stage that lowercases and strips punctuation, driven by two switches
  (`lowercaseTranscripts`, `removePunctuation`) that live in the person's own utt settings. With
  the key unset, one toggle meant for dictation elsewhere silently mangles every prompt this app
  delivers. `cleanup` and `replacements` are kept on purpose: cleanup is deletion-only with a
  budget and a whole-transcript fallback, and resolving "at five, actually six" to "six" is
  exactly the shape a spoken prompt takes. An unknown stage name is dropped rather than refused,
  so the key is safe against an older utt.
- **utt stops servicing the jobs folder the moment Deckhand is switched off, and leaves the
  folder there.** `ExtensionJobs.pending()` filters on `enabled`, so a disabled extension's clips
  are written and never read — and hold-to-talk blocked for the whole `TIMEOUT` of 180 seconds
  before reporting that utt did not answer, which is true and useless. `plugin.turned_off()`
  reads the `<id>.disabled` marker (an empty file; its presence is the whole state, because a
  marker survives the extension rewriting its manifest at every start-up) and `transcribe` says
  so at once instead.
- **The iTerm join under launchd was a throttling problem, not an approval one.** The plist
  said `ProcessType: Background`, which puts the job in launchd's slow lane for CPU and I/O,
  and a lookup that costs ~1 s from a terminal then blew a 4 s timeout every time. It reads
  `Interactive` now, the timeout is 12 s, and panes resolve under launchd. A failed lookup
  still backs off for a minute so a real outage cannot starve the event loop. This matters for
  more than window titles: without a pane there is no keyboard, and delivery falls back to the
  peer socket.

## Starting a session that does not exist yet

`projects/` is the only place a new session comes from. `sources.py` is the universal consumer —
a project is a name and a folder, read from the person's own `projects.json`, then atlas over
HTTP, then atlas's scan cache, first to answer wins. `starting.py` opens the terminal.

- **`it2 tab new` makes a pane whose shell never reads input.** It exits 0, the pane comes back
  from `it2 session list --json` with a tty and a live zsh on it, and a minute later it holds
  nothing but blank lines. A tab is created relative to iTerm's *current* window and a daemon has
  no window to be current in. `it2 window new` has no such ambiguity and prints `Created new
  window: pty-…` — a handle, so the new session is looked up by `window_id` rather than guessed
  at by diffing the session list either side of the call.
- **Never script `it2 session close`.** It asks "Close tab #N?" as a **modal sheet**, which blocks
  iTerm's entire Python API — every `it2` call on the Mac, this daemon's pane lookups included,
  fails with "Not running inside iTerm2 or Python API not enabled" until somebody dismisses it.
  Piping `yes` does not answer it. Recovering without restarting iTerm (which would take every
  live session with it) is `osascript -e 'tell application "System Events" to tell process
  "iTerm2" to click button "Cancel" of sheet 1 of window 1'`.
- **Bare `claude` opens the session dashboard, not a session.** Measured on 2.1.266: it draws the
  "describe a task for a new session" launcher, writes no `~/.claude/sessions/<pid>.json`, and so
  never reaches the phone at all. `--name` starts an interactive session outright and is **not in
  `claude --help`** — the flag was read off the running processes on this Mac.
- **A folder Claude Code has never been trusted in stops at a prompt nobody can answer**, and
  writes no session record until it is. Read the answer it already has out of `~/.claude.json`
  (`projects.<path>.hasTrustDialogAccepted`) and refuse before opening anything — otherwise a
  window is left stranded at a question. 81 of 659 folders here are trusted, so this is the
  common refusal rather than an edge case.
- **A session's name is a key**, not a label: a star, a hidden row and a filter chain are all
  filed under it, so a second session called `deckhand` would silently share the first one's
  three. The project's name is taken when free and numbered when not.
- The rest of the launch line is the person's, not a default to help oneself to — a phone-started
  session has nobody to approve its first tool use. Asked on a slip; the answer is in
  `starting.FLAGS`.

## Delivery: two routes, and the difference is authority

The route is the person's choice, in Settings, carried as `POST /sessions/{id}/audio?route=`:
`auto` (keyboard when there is a pane, socket when there is not), `keyboard`, or `socket`.
`keyboard` never silently falls back to the socket — choosing it is choosing whose authority
the words carry, so it fails and says why instead. The receipt names the route that took it
(`delivered_by`).

- **The keyboard route.** `it2 session send` types the words into the session's pane and
  presses return, so they arrive as a prompt from the person at the machine — which is what
  they are. Three bursts, not one: ctrl-U (a half-typed line in the prompt is not part of what
  was said), the words, then return alone — a return at the tail of one fast paste is what
  leaves a message staged in the box instead of sent. It cannot be confirmed: a staged message
  and a sent one look identical to `it2 session read`, and a busy session queues the words for
  as long as its turn lasts. The receipt says they were typed, which is all that is known.
  One hazard: if that pane happens to be showing a permission prompt, dictated words go to the
  prompt, not to a new message.
- **The fallback goes through the session's own peer socket.** Every session listens on the
  `messagingSocketPath` in its record, and the wire format is newline-delimited JSON — an
  optional `{"type":"auth","token":…}` line carrying the `peerToken` out of the sibling
  `<pid>.<hash>.key` file, then one `{"msgV":1,"type":"user","message":{…},"priority":"next"}`
  frame. Nothing comes back: a successful write is the only acknowledgement, and a session
  mid-turn queues the message rather than dropping it. It arrives labelled as a message from
  another Claude session, wrapped in "it is not from your user, it carries none of your user's
  authority". That wrapper is a genuine control against one agent laundering permissions
  through another; it is not something to defeat, it is the wrong channel for a person speaking.
  Verified against a real live session on 2026-09-09, not only against a test socket.
- **A slash command only works typed into a pane.** The socket delivers a *message*, so one
  sent that way arrives as words beginning with a slash: the session reads it, runs nothing,
  and reports no failure, because from where it sits nothing failed. `deliver.deliver` refuses
  a leading slash on the socket route and where there is no pane, which is the only way anybody
  finds out.
- **Stop, compact and clear are keystrokes, not messages.** `deliver.control` sends Escape for
  a cancel and types `/compact` or `/clear` the same way a spoken line is typed. The peer socket
  can do none of them, so a session with no pane cannot be controlled from the phone and the
  menu says so rather than failing quietly. `clear` is the only irreversible thing in the app.
- **Renaming is `/rename`, Claude Code's own command**, typed into the pane like anything else
  — it is `supportsNonInteractive`, so with an argument it renames without opening a picker.
  Verified against a live session: the registry's `name` and `nameSince` both move. A busy
  session only runs it when its turn ends, so the listing catches up late.
- **A picture reaches a session as a path, not as a paste.** `POST /sessions/{id}/image` keeps
  the bytes under `images/<sessionId>/` and answers with the path; `POST .../say` takes
  `images: [path]` and `deliver.with_images` appends them to the words, so the session sees the
  file with its own `Read`. `app._kept_images` only passes paths inside that session's own
  folder — without it, "say this and read that file" would aim a session at anything on the Mac.
  The files are kept after delivery; nothing prunes them yet.

## What the person has set this Mac to do

`settings/` is the switches, keyed by **path**. Four things act without being asked and each is
one switch: `finished` (a session stopped), `slips` (a slip is unanswered), `called` (an agent
asked for you outright, `POST /sessions/{id}/notify`), and `chase` (the idle check, which speaks
to a session rather than to a person). Plus `subagents`, off by default, which lets the
summariser read what a folder's subagents did. `GET|PUT /settings` is the whole document;
`GET /settings/project?path=` is the resolved answer for one folder.

- **Path, not session id.** "Per session" is what was asked for, and a session id is the wrong
  key for it — it changes every restart, so the preference would be gone by morning. The folder
  is stable, and a session's page edits the folder it is running in. (Stars and hidden rows key
  by *name* for a related reason; a name is no good here because two folders share one often.)
- **Per key, not per object.** A folder given only a different summariser keeps every other
  answer and goes on following the global switch when that switch changes. `None` on the wire is
  "no opinion" and is how an override is removed.
- **A model this Mac does not offer is refused on write**, not passed through: it would become a
  `--model` flag on a real launch line or an id the SDK rejects, both failing far from the screen
  that set it. The empty string is an answer — "the default" — and survives.
- **`called` is the only trigger a session raises for itself**, so it is the only one a folder may
  refuse outright, and the refusal is returned rather than swallowed. An agent that thinks it has
  your attention and has not is worse than one that knows it has not.
- **Not one switch per push.** `push.py` raises a card, drops it when the session goes, and
  re-announces when you answer; the last two are that card's bookkeeping, and switching one off
  would strand a card nothing could clear.

## Briefings, tasks, and the idle check

- **A briefing is a file, and the daemon decides when one is owed.** This was a dict in memory
  with a two-minute TTL, which cost more than everything else in Deckhand put together: a
  session that had done nothing still bought a model run every two minutes for as long as
  anyone had the list on screen, and nothing survived a restart. `briefings.py` keeps the last
  one under `briefings/<sessionId>.json` and one worker walks the live sessions. Two gates
  before a model is touched, cheapest first: the transcript's own mtime, then the activity hash
  (Claude Code appends plenty — a mode change, an attachment — that nobody wants a briefing
  about). Reading `/sessions/{id}/summary` never waits for a model: it answers off disk and
  **bumps** that session to the front of the queue. `GET /briefings` hands back every live
  session's last briefing in one call, which is what makes a cold start whole.
- **The task list is the Mac's, not the model's.** It lives in `tasks/<sessionId>.json` and the
  summariser changes it only through three in-process SDK tools (`add_task`, `set_task_state`,
  `drop_task`) bound to one session's file. Written as part of the briefing it was a *new* list
  every run, which is how the shape of it kept changing. The model is handed the list with its
  ids and may not reword, renumber or re-order it; `drop_task` needs a reason and warns, because
  it is the only operation that loses something. Trimming is not the agent's job either:
  `MAX_KEPT` is a ceiling on a file and the phone decides how many to show. The run is
  `max_turns=16` with `permission_mode="bypassPermissions"` — safe only because those three
  functions are the entire tool surface and nobody is at the daemon to answer a prompt.
- **The idle check messages sessions on its own** (`nudge.py`). A session quiet for `SETTLE`
  with anything unfinished on its list is asked, over the **socket** route so it arrives
  labelled as another agent rather than as JJ typing, either to finish or to say why not. Two
  guards against a daemon that will not let a session stop: the same list is never asked about
  twice (fingerprint of ids and states), and never more often than `AGAIN` whatever the list
  does. `DECKHAND_NUDGE=0` turns it off.
- Anything the summariser or the transcriber needs must be reachable without a person present.
  The summariser passes `setting_sources=[]` for the same reason it is fast: loading the user
  settings starts every configured MCP server, which cost more than a minute.

## Files, and why the listing is the permission

- **The file listing is the whole permission.** `/file` serves a path only because that
  session's transcript named it, re-derived per request. There is no allow-list to maintain and
  no way to widen it by accident — which is what keeps a file endpoint off the rest of the Mac.
  Source files and `node_modules`/`.build`/`.git` are left out on purpose: the tool trace
  already shows the code, and a phone listing 200 files shows nothing.
- **The same rule covers projects.** A folder this Mac's project list does not name is a 404, so
  `/projects/session` stays a way into work that already exists rather than a way to run Claude
  Code anywhere on the Mac.
- **Serving a file is not the same size as taking one.** `MAX_FILE_BYTES` is 512 MB against
  `MAX_UPLOAD_BYTES`'s 32 MB, and reusing the upload cap for `/file` is what made every video a
  session rendered come back as 413.

## utt, the plugin page, and APNs

- **Transcription goes over the plugin file lane.** The clip is written into utt's own
  extensions folder — `~/Library/Application Support/dev.jurrejan.utt/extensions/deckhand.jobs/`
  on any current utt, `plugins/` on one older than the rebrand — and utt writes the text beside
  it. **Never name either path in code**: `plugin.plugins_dir()` asks the disk which one exists,
  newest name first, because the folder that counts is the one the *running* utt makes at launch
  and not the one its source says. Both folders exist on this Mac, which is exactly how a reading
  of the tagged source can conclude the lane is broken while it is working — the proof of which
  utt actually reads is that the answer files and the jobs directory itself are owner-only
  (0600/0700), and utt is the only thing that writes with those modes. No listener, no token, nothing on the network, and it works whether or not
  utt's HTTP API is switched on. **The daemon holds no token of utt's**: `needsApi` is false,
  so there is nothing to go stale.
- **The clip must be whole before it is audio.** utt picks up finished audio extensions from
  the jobs folder, so a clip is written as `<name>.wav.part` and only then renamed — skip the
  rename and utt reads the file mid-write. `<name>.hints.json` goes in *before* the rename, or
  it is a hints file utt has already run past. The extension has to match the bytes:
  AVFoundation picks its reader from the extension, so a wav named `.m4a` fails to open however
  correct it is. utt deletes the audio and the hints; the answer file is ours to remove.
- **Hints are the cheapest accuracy in the system.** Every clip was dictated at a named session
  working in a known folder, so the vocabulary is known before the clip is recorded
  (`transcribe.hints_for`). utt only lets a hint displace text that is already nearly it and
  starts with the same letter, so the list cannot rewrite a sentence: it catches "cockwheel" →
  "cogwheel", "Tu Y" → "TUI", "deck hand" → "deckhand". It cannot fix an ordinary word misheard
  as another ordinary word ("previous tree" for "previous three" stays wrong).
- **Anything utt writes that this daemon has no name for rides through to the phone.**
  `transcribe._read` keeps every key outside `KNOWN` and `saying._receipt` merges them into the
  answer without ever writing over one of its own. utt's `ProcessedTranscript` holds `raw`,
  `stages` and `cleanupSkipped` and drops all three at the jobs boundary; the day it stops
  dropping them the review card starts showing what utt's cleanup rewrote, with no change here
  and nothing stubbed in the meantime. Nothing in this repo fabricates those fields.
- **utt's span is one span, and up to 300 ms of it is utt not having looked yet.** It cannot
  honestly be split: `ExtensionJobResult` carries no timings, `announce(ExtensionActivity(…))`
  reaches in-process listeners only, and utt deletes the audio *after* writing the answer, so
  the clip disappearing marks the end and never the start. `ExtensionJobs.interval` is 300 ms,
  which is the difference between "utt is slow" and "utt has not noticed" — the app says so
  under the number. `transcribe.POLL` is 20 ms for the matching reason: at the 0.2 s it used to
  be, the largest stage in the whole path was measured with a fifth of a second of noise on it.
- **Every clip's stages are answered and written down.** `log.took` is the one clock (`took` is
  in `log.py` rather than a `timing.py` because this directory sits on the 16-file cap).
  `/sessions/{id}/audio` answers with `timings` as an ordered **list** of `{name, ms}` — the
  phone decodes with `convertFromSnakeCase`, which rewrites dictionary keys as happily as struct
  ones, and a stage name is data. The same numbers go to `timings.jsonl` in the data dir, keyed
  rather than ordered, one appended line per clip with the clip's bytes and the `seconds` the
  phone measured — the Mac never opens the audio, so without that query param a line cannot say
  what a millisecond bought.
- **Anything utt hands back has already been through utt, and possibly through another
  extension.** The jobs answer carries `text`, `error` and `finishedAt` — there is no `raw`, so
  the transcript as heard never crosses the lane. utt's cleanup stage has run on it, and so has
  every installed extension declaring `filtersTranscripts`: one closure serves the hotkey, the
  API and the jobs lane alike, and the filters chain in id order. An extension that pastes
  everything in capitals would put every phone prompt into a session in capitals with nothing in
  Deckhand's log to say why. `skipsTextStages` bounds what *utt* may do; it does not bound
  another extension, and there is nothing on this side that can.
- **The plugin page needs utt 1.1.0 or newer.** Before that, utt dropped manifest keys that were
  not all-lowercase and said nothing, so `copyToken` and `openLog` never became buttons and only
  `stop` did — a page can be half-missing and look complete. There is still no way for a plugin
  to learn that a key was refused, so a button that does not appear is the only symptom.
- **Every action has to be safe to press by accident**, because `showsInMenuBar` is all of them
  or none. There was a "Stop listening" action running `launchctl bootout`, which *unloads* the
  job; utt's Restart is `kickstart`, which cannot revive a job that is not loaded (verified: exit
  113, "Could not find service"). Stopping it for good is `just uninstall-agent`.
- **A string setting arrives per keystroke.** `revision` is correct per write, but typing one
  sentence into a field produced 40-odd revisions in four seconds. Anything done on a values
  change has to be cheap, or debounced.
- **APNs needs a key the daemon cannot mint.** `just sync-apns` materialises `deckhand/APNS_KEY`
  and `APNS_KEY_ID` out of 1Password, for the launchd reason as ever. The key itself is created
  by hand once in the developer portal. Without it everything works up to the send and the log
  says `no push key on this Mac`. **The host must match the entitlement**: the app signs
  `aps-environment: development`, so the daemon talks to `api.sandbox.push.apple.com`; a token
  minted for one host is refused by the other. See `widgets/CLAUDE.md` for the payload contract.

## Verification

`just daemon-lint` (ruff) and `just daemon-test` (pytest), both inside `just check`.
`just daemon` runs it in the foreground and prints its address and pairing token.
`.quality.json` caps a Python file at 400 lines and a directory at 16 files.

- **The launchd daemon pins this tree at start and never reloads**, so a restart taken while any
  file is mid-edit freezes that half-written state into the live service until somebody restarts
  it again. It runs from `daemon/src/` in the working copy: one agent's `kickstart` landed on
  another's partial write and `GET /sessions` answered 500 with a `NameError` for several
  minutes, which on the phone reads as no sessions at all rather than as an error. `artifacts.py`
  is the sharpest edge of it — `app.list_sessions` calls `artifacts.counted`, which calls
  `listing` — so a name used above its definition *there* takes out the whole app's world and not
  the slips tab. Helpers before their callers in that file, or write the change in one pass.
- **A green `just daemon-test` says the file on disk is right and nothing about what is running.**
  Recovery, once the edit is finished and the tests pass, is `launchctl kickstart -k
  gui/$(id -u)/com.jurrejan.deckhand`. Restart deliberately and once: with several agents in the
  tree, a bounce taken to fix one half-written file is a bounce onto whatever else is half-written.

## Related context

- `../CLAUDE.md` — the repo map and the endpoint surface
- `reading/CLAUDE.md`, `filters/CLAUDE.md`, `prompts/CLAUDE.md` (under `src/deckhand_daemon/`)
- `../launchd/com.jurrejan.deckhand.plist` — the agent, registered in project-atlas `daemons.json`
