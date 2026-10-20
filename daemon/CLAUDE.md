# The daemon

## What this is

The Mac half. A FastAPI service on port 4180 that lists every live Claude Code session,
serves the last rounds of its conversation, takes voice clips from the phone, and writes
the words back into that session. It runs as launchd agent `com.jurrejan.deckhand` and
logs to `~/Library/Logs/Deckhand/deckhand.log`.

State lives in `~/Library/Application Support/Deckhand/` — `token`, `audio/<sessionId>/`,
`images/<sessionId>/`, `tasks/<sessionId>.json`, `briefings/<sessionId>.json`,
`queue/<sessionId>.json`, `timings.jsonl`, `nudged.json`, `space.json`.

## Mental model

```
app.py          # the endpoints, and nothing else
__init__.py     # the version, and `main` — the process from the outside, `--hand` included
config.py       # data dir, token, port
log.py          # the one log file, in ~/Library/Logs
sessions/       # which Claude, Codex and OpenCode sessions are alive, their pane, what they spent
fleet/          # every other machine: the registry, the ssh link, the hand, the merge
projects/       # what folders there are, and starting a session in one
reading/        # everything that reads a transcript and nothing that writes one
deliver.py      # the words go into the session, by keyboard or by socket
saying.py       # what a spoken line becomes before it is delivered
orders/         # one session's standing orders, and how they get in front of a message
filters/        # what happens to a prompt between the phone and the session
projects/       # the folders on this Mac, and starting a session in one of them
prompts/        # every prompt this daemon sends a model, and nothing else
manager/       # the manager: its conversation, its facade of tools, its run, its routes
mcp/            # the fourteen tools a session inside this Mac gets, over stdio and as `deckhand`
space/          # the headset's space: planes, poses, its camera, /windows passed through to :4181
briefings.py    # where briefings are kept, and the one worker that keeps them current
summarize.py    # what happened since you last spoke, via the Claude Agent SDK
tasks.py        # the person's list of asks, and the only three tools that may change it
nudge.py        # asks a session that stopped about the asks still open on its list
files.py        # what the session touched that a person could open, and the permission
artifacts.py    # slips: what a session left for the phone to answer
transcribe.py   # utt turns a clip into text, through its jobs folder
plugin.py       # Deckhand's page inside utt: the manifest, its settings, its buttons
beacon.py       # saying on the LAN where this Mac answers, so the phone need not be told
presence.py     # `laptop`, `phone` or `headset`: idle, the lock flag, the headset's beat, utt's cover
push/           # the Lock Screen: `sending.py` is APNs, `__init__.py` is what is worth a card
tray/           # what needs the person, on every machine, and what happened: docs/tray.md
```

Before editing under `reading/`, `filters/` or `prompts/`, read that folder's own CLAUDE.md.
`manager/` carries its own context in its `__init__.py` docstring, and `manager/doing.py`'s
docstring is the one to read before adding a tool — the line it draws is an authority decision,
not a convenience.
`projects/` carries its own context in its `__init__.py` docstring — read that first; it is the
one lane that *makes* a session rather than speaking to one.

## The join that makes this work

Claude Code writes `~/.claude/sessions/<pid>.json` for every running session — sessionId,
cwd, name, and a live busy/idle status. Those files outlive the process, so a record only
counts when `ps` still shows that pid. `ps` gives the tty, `tmux list-panes -a` maps
tty → tmux pane. No hooks, no polling of a terminal's title. tmux replaced iTerm here on
2026-10-15: iTerm's 3.7 beta crashed on opening a tab, and with it every session's pane. The
wire keeps iTerm's names (`iterm`, `pane.iterm_session_id`) because the installed apps decode them.

**`~/.claude` is not the only config dir.** A session started with
`CLAUDE_CONFIG_DIR=~/.claude-pimpelmees` writes its record, its key file and its transcript there
and nothing under `~/.claude`, so it was simply never listed. `config.claude_homes` is the home plus
every sibling `<home>-*` holding a `sessions/` folder (`~/.claude-monitor` has none and is not one),
and the listing, the peer key, the transcript lookup and the MCP's own record all read every one.
Settings, the trust record and the week cache still come from `~/.claude` alone: the pimpelmees dir
symlinks its `settings.json` back there.

Sessions with no tmux pane are hidden — unless tmux answers nothing at all (no server), in which
case every live session is listed so the app still works. `/health` and `/sessions` both carry an
`iterm` field saying whether pane data is trustworthy.

- **A session id is the conversation, not the session.** `/clear` retires it and starts a new
  one under the *same* pid, pane, inbox socket and name — so nothing the phone can see changes,
  and a page opened before the clear is left addressing an id this Mac no longer answers to.
  That was a prompt that silently went nowhere. `sessions.succeeded_by` remembers which pid an
  id was retired from and `saying.session_or_404` follows it, which makes that the one lookup
  allowed to answer with a session other than the one asked for. Both maps drop a pid the
  moment it stops running, and that is not tidiness: pids are recycled, and an id left pointing
  at a dead one would resolve to whatever unrelated session got that number next.
- The pane map is cached for 3 s because the phone polls every few, and a failed lookup backs
  off for a minute.
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
- **The pane join under launchd was a throttling problem, not an approval one** (measured with
  `it2`, before tmux). The plist
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

- **A new session is a detached tmux window** (`tmux.open_window`), in the tmux session the
  person is attached to, else the most recently used, named `deckhand-<name>` so the window list
  shows which came from a phone. Detached, so the person's own view never jumps. No tmux server
  at all makes a session of its own. Verified 2026-10-15 against a separate tmux server: the
  receipt carries the new pane.
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
`auto` (keyboard when there is a pane and nobody at the laptop, socket otherwise — a slash
command still types), `keyboard`, or `socket`.
`keyboard` never silently falls back to the socket — choosing it is choosing whose authority
the words carry, so it fails and says why instead. The receipt names the route that took it
(`delivered_by`).

- **The keyboard route.** `tmux send-keys -l` types the words into the session's pane and
  presses return, so they arrive as a prompt from the person at the machine — which is what
  they are. Ctrl-U (a half-typed line in the prompt is not part of what was said), then the
  words, then the return — **each in a write of its own**. **Both keys are CSI-u escape
  sequences** — `\x1b[117;5u` and `\x1b[13u` — rather than the bare bytes they stand for, and
  that spelling is why a long prompt submits at all. Claude Code's input tokenizer splits a
  control byte out as its own keypress only when the whole read is under 64 bytes; in a longer
  read it is folded into the surrounding text run. The words and the return are separate writes,
  but a session slow to drain its tty takes both in one read — measured against an inert pane, a
  reader stalled for six seconds got a single 122-byte read holding the words *and* the return —
  and at that size a bare return is typed rather than pressed, which is a prompt left sitting in
  the box. An escape sequence is tokenised out of a read of any size. `send-keys -l` hands those
  bytes to the pane exactly as spelled — verified 2026-10-15 under tmux 3.5a: a 1263-byte prompt
  in two bursts, confirmed by the transcript and answered, then `/exit` the same way.
- **That spelling saves the keys and does nothing for the words.** A pane's tty hands Claude
  Code at most **1022 bytes per read**, so one `send-keys` longer than that arrives as two
  reads a fraction of a millisecond apart — and Claude Code keeps only one of them. Measured on
  2026-09-13 against a live session, a 1212-character prompt: sent as one write with ctrl-U on
  its front, mangled **13 times in 52**, every failure arriving with its **first 1014 characters
  gone** and only the tail submitted. That is worse than a prompt that never went: it went, it
  said something else, and the daemon reported it delivered. Splitting ctrl-U off its own write
  took it to 1 in 14 and dropping ctrl-U entirely to 1 in 24 — neither is a fix, because the
  split is in the buffer and not in the ctrl-U. Chopping the words into writes under the buffer
  (`deliver.BURST`, counted in **bytes**, because a character must never be cut in half) is:
  0 in 36, including at 4000 characters. A tiny message cannot hit this; anything over roughly
  a thousand characters always did, which is most of a spoken paragraph.
- **`send-keys` exiting 0 says the keys were accepted, never that the prompt was submitted.** A
  staged message and a sent one look identical on the screen — but not to the session's own
  transcript, which is the log of what arrived: an idle session writes the prompt as a turn and a
  busy one writes a `queue-operation` for its inbox, and both land inside a second (measured over
  130 real sends: median 0.5 s, slowest 2.2 s). `deliver._arrived` watches the bytes appended to
  that file for **the whole message**, not its opening — the half that survives the failure above
  is the tail, so an opening that matched would be the half that was lost. Not found inside
  `SUBMITTED`: the return is pressed once more (on a box the first one emptied that does nothing,
  so it cannot send anything twice) and then the delivery is reported as **failed**. A keyboard
  delivery that failed this way never falls through to the socket, even on `auto` — the words are
  already in that session's box and saying them again down another route leaves it holding both.
  One hazard this cannot see: if that pane happens to be showing a permission prompt, dictated
  words go to the prompt, not to a new message.
- **Ctrl-U clears one wrapped line, so the box is cleared with a hundred** (`deliver.CLEAR_BOX`).
- **A transcript that is late is not a prompt left unsent**: a prompt-submit hook can hold it back
  for seconds, so before saying "unsent" the box itself is read (`panes.holds`).
- **A box set to a teammate (`─ @name ─` over it) is taken back to the lead before anything is
  typed**, one checked key at a time, or the words take the inbox — `sessions/teammates.py`.
- **A session on another machine takes the same last step, one machine over.** `deliver.deliver`
  is the one branch, because every caller in this daemon already routes through it — the filter
  chain, the standing orders and the delivery record have all run here by then, and running any
  of them again on the far side would be the shape of bug that looks like it works. Nothing above
  that branch changes: the keyboard route has already refused, because a remote session has no
  pane, and so has a slash command, for the same reason. On Fractal the inbox is a named pipe
  rather than an `AF_UNIX` socket; the frames are identical and only the door differs.
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
- **Standing orders ride on a prompt and never on their own.** `orders/` keeps what the person
  told one session to keep in mind, filed by session id; `saying._with_orders` puts it in front of
  the words at the two doors a prompt from the phone comes through, after the filter chain and
  before `deliver`. Not inside `deliver`, which also carries the idle check and a slip's answer —
  neither of those is the person speaking, and their words have no business on a message they did
  not send. Every prompt rather than once, because the daemon does not own the session's context: a
  `/clear`, a compact it never saw, or a queued prompt lost to a restart each make "I already said
  this" false, and each fails the same silent way. The cost is bounded by `prompts/orders.md`'s own
  `limit` instead. An empty field adds **nothing** — `carry` hands back the identical string, so a
  session nobody has given orders to cannot be told apart from one on a daemon without this feature.
- **A picture reaches a session as a path, not as a paste.** `POST /sessions/{id}/image` keeps
  the bytes under `images/<sessionId>/` and answers with the path; `POST .../say` takes
  `images: [path]` and `deliver.with_images` appends them to the words, so the session sees the
  file with its own `Read`. `app._kept_images` only passes paths inside that session's own
  folder — without it, "say this and read that file" would aim a session at anything on the Mac.
  The files are kept after delivery; nothing prunes them yet.

## Codex threads: the second provider

`sessions/codex.py` lists the Codex app server's threads beside Claude Code's sessions, and every
row says which it is in `provider`. Read off codex-cli 0.154.0 / app server 0.153.4 and its
generated schema on 2026-09-13.

- **The control socket is WebSocket.** `<CODEX_HOME>/app-server-control/app-server-control.sock`
  (`DECKHAND_CODEX_HOME`, else `~/.codex`) answers an HTTP upgrade and closes after 0 bytes if the
  handshake carries the library's default `User-Agent`, `Origin` or deflate offer. `codex app-server
  proxy` spoken to in newline JSON never answers. `initialized` is a notification, with no id.
- **Listed: loaded, top-level, `active` or `idle`.** `thread/read` per id off `thread/loaded/list`,
  never `thread/list`, which took 2.8 s, stopped at 100 threads and missed 5 of 7 loaded ids. Once
  per listing, a 2 s timeout, then 30 s of not asking after a failure — the iTerm pattern — so a
  dead app server costs `/sessions` one timeout and never its Claude rows. `/health` carries
  `codex`. A Codex row has no pane and is exempt from the no-pane rule.
- **Its only input lane carries the person's authority.** `turn/start` when idle and `turn/steer`
  into the running turn when busy both arrive as the user typing, so `auto` and `keyboard` take
  them (`delivered_by: codex-direct | codex-steered`) and `socket` is refused, never substituted.
  So is a slash. The branch is one line in `deliver.deliver`, after the chain, the orders and the
  record. Whatever speaks as an agent — the manager's `say_to_session`, the idle check, the MCP
  tool — refuses or skips a Codex session; the briefings worker skips them for want of a transcript.
- **What it cannot share is answered in one middleware**, `sessions/codex_routes.py`, an allow-list
  like `fleet/routing.py`: `turns` and `raw` off `thread/turns/list` with full items, `control`
  `cancel` as `turn/interrupt`, empty `files` and `agents`, and a 409 for `context`, `commands`,
  `queue/clear`, `focus`, `name` and every other control. Ephemeral threads refuse the turns list,
  and that refusal is what the page gets.
- **`POST /projects/session` takes `provider: codex`** and sends `thread/start {cwd, ephemeral:
  false}` with no model, approvals or sandbox, because Codex's own configuration decides. The
  project list still gates it; the trust gate is Claude Code's and does not apply.
- **Only reads have been run against the real server.** `turn/start`, `turn/steer`,
  `turn/interrupt` and `thread/start` are built to the schema and tested behind the `request`
  seam. The link is held open on the assumption that a started thread stays loaded only while
  something is subscribed to it; approval requests on it are dropped, never answered for the person.
- **A Codex row's name is a key like any other**, so an unnamed thread is never its folder's bare
  name: that is the Claude session's star and filter chain. A thread the phone just started has no
  name yet and is `deckhand-codex-<last 4 of its id>` until Codex names it.

## OpenCode sessions: the third provider

`sessions/opencode.py` lists the sessions of this Mac's OpenCode service beside the other two, as
`provider: opencode`. OpenCode 2 runs one background service per user that owns every session and
runs every agent loop, and every TUI is only a client of it — so this is one HTTP API, with no
pid, pane or socket anywhere. Read off OpenCode 2.0.31 and the `/openapi.json` it served on
2026-10-16; every write below was run against the real service with a throwaway session.

- **Found, never started.** `~/.local/state/opencode/service.json` (`DECKHAND_OPENCODE_SERVICE`, else
  `$XDG_STATE_HOME`) holds the URL and a password; the auth is HTTP Basic as `opencode`, which is
  what `@opencode/client/service` builds. Re-read on mtime, because `opencode service restart`
  moves both. No registration, a dead port or a 401 is a listing without OpenCode rows, the same
  2 s timeout and 30 s backoff as Codex. `/health` carries `opencode`.
- **Live is JJ's rule, not a process:** a root session running now (`GET /api/session/active`) or
  updated in the last two hours (`GET /api/session?parentID=null&order=desc`). OpenCode keeps every
  session forever. Children are subagents: `/sessions/{id}/agents` lists them and each reads as a
  conversation, and a subagent's tool dot carries the child's id as its `tool_id`.
- **Both lanes, and the difference is still authority.** `auto` and `keyboard` go in as
  `POST …/prompt` — the person's own input, steering into a busy turn as the TUI does
  (`opencode-direct | opencode-steered`). `socket` goes in as `POST …/synthetic`, which runs the
  loop but tells the model nothing about who sent it, so the words are wrapped in
  `prompts/opencode-peer.md` and the bare words ride in `metadata.deckhand` for the phone to show.
  That is the lane the manager, the idle check and the space notes use — JJ chose it over Codex's
  refusal on 2026-10-16. A throwaway session's model, asked who sent the wrapped message, answered
  "Deckhand, the Mac's daemon, another agent". `auto` never becomes `socket` here: nothing types
  into a pane, so the reason it does for Claude is not there.
- **A slash is OpenCode's own command** (`POST …/command`), else a skill handed to a prompt
  (`skills: [{id}]`). On the agent lane a slash is refused, as on Claude's socket.
- **What the API does that a pane did:** `control cancel` is `POST …/interrupt?resume=true` on the
  session and a plain interrupt on each subagent running under it — without `resume` the words said
  into the turn stay parked and ride in twice with the next prompt. `compact` is
  `POST …/compact`, `/name` is `PATCH {title}` and lands at once, `queue/clear` cancels what is in
  `GET …/inbox`. `clear`, `exit`, `focus` and the CLAUDE.md `context` tree are refused. `deliver`
  carries the first three, so the routes keep their filter carry-over and the record; the reads
  are answered in `sessions/opencode_routes.py`, an allow-list like Codex's.
- **The context figure** is the last finished assistant message's `input + cache.read + cache.write`
  against its model's window from `GET /api/model`, read again only when the session moved.
- **Waiting on you is shown, not answered.** A busy session's pending permission requests and forms
  close its conversation as one line and raise an `asking` card, gated on `slips`. Answering them
  from the phone is the next step; until then OpenCode keeps the turn open for its own clients.
- **The MCP server knows its session from the call.** One `opencode serve` starts `deckhand-mcp`
  once per folder and shares it, and its environment names no session, so the walk up to a
  `claude` process finds nothing. OpenCode puts the calling session in every call's
  `_meta["ai.opencode/sessionID"]`; `mcp/server.py` lifts it for the length of the call and
  `here.mine()` asks the service for that session. Shells OpenCode runs carry
  `OPENCODE_SESSION_ID`, which is how the `deckhand` command and the slip scripts find it.

## What the person has set this Mac to do

`settings/` is the switches, keyed by **path**. Four things act without being asked and each is
one switch: `finished` (a session cleared its whole task list), `slips` (a slip is unanswered),
`called` (an agent asked for you outright, `POST /sessions/{id}/notify`), and `chase` (the idle
check, which speaks to a session rather than to a person). Plus `subagents`, off by default,
which lets the summariser read what a folder's subagents did. `GET|PUT /settings` is the whole document;
`GET /settings/project?path=` is the resolved answer for one folder.

`settings/aliases.py` is the one thing in that folder with no path on it, and deliberately: an
**alias** is a word this Mac always mishears and what it was meant to be, and a voice is not a
property of a folder. `GET|PUT /aliases` is the list, rows of two. The swap runs in
`saying.upload_audio` and `manager/routes.speak_to_manager` the moment utt answers — in front of
the filter chain, which a per-terminal `words` step could never be, and in front of the manager,
which runs no chain at all. `aliases.swap` is the one copy of the whole-word rule; `words.py`
calls it. Read the top of `aliases.py` before moving any of this: it records why utt's own
replacement list cannot be written from here and have it apply to Deckhand's clips.

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
- **Not one switch per push.** `push/` raises a card, ends it when the session goes, and ends
  it when you answer; the last two are that card's bookkeeping, and switching one off would
  strand a card nothing could clear.

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
  session's last briefing in one call, which is what makes a cold start whole — but the phone
  **polls** it, every 6 s from the deck and 12 s from the rail, so it is a hot route and not
  only a first-sweep one. It cost 19 s while `briefings.of` answered `stale` by walking the
  whole queue: a request outliving its own poll interval fills FastAPI's threadpool, and then
  every route queues behind it, `/health` included. Anything added here is paid per session
  per six seconds.
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
  guards against a daemon that will not let a session stop: a session is asked again only when
  an ask it was not already asked about is open, and never more often than `AGAIN` whatever the
  list does. **Ids, never states**: the summariser moves an ask to `doing` on reading the answer
  to this very question ("waiting on JJ" is blocked work), so counting states made every answer
  arm the next one. **What was asked is kept in `nudged.json`, not in the process** — the daemon
  restarted 11 times on 2026-09-14 and each restart asked every owing session again.
  `DECKHAND_NUDGE=0` turns it off. **A session whose subagents are still working is not
  quiet** — stopping a turn with a background agent running is the ordinary way to leave one
  going, and asking then interrupts the work to ask whether the work is done. `agents.alive`
  answers it for the price of a `stat` per agent and the quiet clock restarts, exactly as `busy`
  does; `reading/CLAUDE.md` carries what makes that answer honest.
- Anything the summariser or the transcriber needs must be reachable without a person present.
  The summariser passes `setting_sources=[]` for the same reason it is fast: loading the user
  settings starts every configured MCP server, which cost more than a minute.

## The manager

One Claude Agent SDK conversation living in this daemon, reached from the phone's own panel. The
whole of it is `docs/manager.md`; three things are worth having here.

- **The conversation is a file with a cursor, and the phone never waits for a model.**
  `POST /manager/say` answers the moment the words are written down, `manager.agent.watch()`
  answers into the same file, and `GET /manager?since=` brings back what is new. Same shape as
  `briefings`, same reason: a run takes seconds and an HTTP client waits twenty.
- **One `ClaudeSDKClient`, held open for the daemon's life, so it is a session like any other.**
  Claude Code lists it as `deckhand-manager` with an inbox socket, so other sessions find it with
  `ListAgents` and `SendMessage` it; it answers them with `SendMessage`, its one built-in tool. It
  was one `query()` per turn once, alive for seconds and so never findable. It must run
  `bypassPermissions`: a session that prompts holds every message from one that bypasses
  (`peer_message_hold`, `mode-mismatch`), and every session on this Mac bypasses. A restart
  reopens it with `resume=` the id kept in the conversation file; a resume that never answers is
  dropped once and the panel is told, otherwise a pruned SDK transcript leaves a dead manager.
- **The refusals are enforced by absence, not by a check.** `say_to_session` has no route
  parameter; there is no tool for stop, compact, clear, rename, answering a slip or writing a
  filter chain, and `set_switch` does not offer `route`. The manager is a Claude session, so its
  words reach another session down that session's inbox socket carrying none of the person's
  authority — that is the same invariant the delivery routes answer and it decides the surface.
  `start_session` *is* allowed, unlike in `docs/agent-surface.md`, because it only ever runs
  because somebody spoke into the panel and both existing gates are unchanged.

## Files, and why the listing is the permission

- **The file listing is the whole permission.** `/file` serves a path only because that
  session's transcript named it, re-derived per request. There is no allow-list to maintain and
  no way to widen it by accident — which is what keeps a file endpoint off the rest of the Mac.
  Source files and `node_modules`/`.build`/`.git` are left out on purpose: the tool trace
  already shows the code, and a phone listing 200 files shows nothing.
- **A connected folder is the one way to widen it, and only the person makes one** — from the
  phone, per project (`GET|PUT /sessions/{id}/folders`); see `settings/folders.py`.
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
- **utt's span opens into utt's own stages, and the wait in front of them is ours to derive.**
  On `feature/job-answer` utt answers with a `timings` of its own — milliseconds keyed by
  `TranscriptStage`'s raw values, `decode` for the recogniser. What it cannot report is the part
  of our span that was over before utt looked, so `transcribe.inside` derives it: our span minus
  everything utt accounted for, clamped, drawn as `waiting`. That is the number that matters
  most here — measured at 2.1 s and 10.1 s for the *same clip* minutes apart, because
  `ExtensionJobs.pending()` takes what is already queued first. On a utt that measures nothing
  the span stays one opaque number carrying the 300 ms warning, and that is the degraded case
  rather than the shape the code is built around. Never split it off `startedAt`/`finishedAt`:
  those are whole-second ISO strings (a one-second quantum on a three-second span), and on a utt
  older than that branch `finishedAt` is stamped at *pickup* and means the opposite of its name.
  `transcribe.POLL` is 20 ms for the matching reason: at the 0.2 s it used to be, the largest
  stage in the whole path was measured with a fifth of a second of noise on it.
- **utt calls its breakdown `timings` and so do we, and only one of them may win.** utt's is the
  inside of our `utt` stage, so `_staged` nests it there and the merge loop skips that key
  outright. Every *other* collision is logged rather than dropped: the pass-through used to be a
  `setdefault`, which would have taken a key utt newly claimed and lost it in silence — the one
  failure mode nobody would ever have noticed.
- **A timing and a `stage` are different records and disagree on purpose.** `stages` is what
  *changed the words*; a timing is reported for anything that *ran*. In Dutch the cleanup model
  runs, succeeds and hands the text back identical, so it is timed and absent from `stages`.
  Absence from `stages` therefore means **unchanged** and nothing more — never "reviewed",
  "approved" or "checked", in any language.
- **Every clip's stages are answered and written down.** `log.took` is the one clock (`took` is
  in `log.py` rather than a `timing.py` because this directory sits on the 16-file cap).
  `/sessions/{id}/audio` answers with `timings` as an ordered **list** of `{name, ms}` — the
  phone decodes with `convertFromSnakeCase`, which rewrites dictionary keys as happily as struct
  ones, and a stage name is data. The same numbers go to `timings.jsonl` in the data dir, keyed
  rather than ordered, one appended line per clip with the clip's bytes and the `seconds` the
  phone measured — the Mac never opens the audio, so without that query param a line cannot say
  what a millisecond bought. Everything utt said for itself rides along under `utt`, so a run
  can be compared against `duration`, utt's own count of the audio, the day utt sends one.
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
- **One card is one session, and three things can put one there.** A new unanswered slip and
  `POST /sessions/{id}/notify` are both `asking` — they may raise a card and they carry the sound.
  A session's task list going from something to nothing is `finished` — silent, and it may only
  ever *update* a card that is already up. A turn merely ending raises nothing: it did, 294 times
  in 28 hours. `push.end` takes a card off the Lock Screen when its session is answered or goes
  away, because iOS's own retirement is hours and a parked card teaches you to ignore the feature.
  Activity tokens are filed by session id, since the phone hands one over per live card.
- **APNs needs a key the daemon cannot mint.** `just sync-apns` materialises `deckhand/APNS_KEY`
  and `APNS_KEY_ID` out of 1Password, for the launchd reason as ever. The key itself is created
  by hand once in the developer portal. Without it everything works up to the send and the log
  says `no push key on this Mac`. **The host must match the entitlement**: the app signs
  `aps-environment: development`, so the daemon talks to `api.sandbox.push.apple.com`; a token
  minted for one host is refused by the other. See `widgets/CLAUDE.md` for the payload contract.

## Being found on the LAN

`beacon.py` advertises `_deckhand._tcp` on 4180 from the FastAPI lifespan, and the phone's
pairing screen browses for it. Discovery answers *where*; the pairing code is still typed once.

- **The addresses are in the TXT record, not in the SRV target.** `host=` and `lan=`, plus
  `name=` and `version=`, so the phone reads a beacon off the browse result itself and never
  opens a connection to resolve one.
- **Both of them come out of `config`, and neither is worked out again in `beacon.py`.**
  `host=` is `urlsplit(base_url()).netloc` and `lan=` is `lan_address()` with the port on it —
  the same two functions `/health` answers with. This is the same question asked in a second
  place, and two answers to one question is how they come apart: the argument
  `settings/routes.for_project` makes for resolving a folder's switches on the Mac.
- **Two addresses because one of them moves.** The `.local` name is first, because it survives
  DHCP; the raw IP is behind it, because mDNS name resolution is not something this Mac can
  promise on every link. Measured 2026-09-14, hours apart: `lan` was `172.20.10.8` (an iPhone
  personal-hotspot range) and then `192.168.178.180` (the house). The name did not move. The
  phone asks `/health` whether the **name** resolves for it and takes the IP when it does not;
  the IP itself is not probed, for the reason written on `Beacon.answering`.
- **It is `dns-sd -R` held open as a child, not a Python dependency.** The registration lives
  exactly as long as that process, so there is no unregister path to get wrong. Verified on
  2026-09-14: `beacon.start()` puts the service on two interfaces, `dns-sd -L` reads back
  `host=m2-2.local name=deckhand version=0.1.0`, and after `beacon.stop()` the identical browse
  finds nothing.
- **The child is in this daemon's process group, and that is the whole of how it dies.** Measured
  the same day: `dns-sd` comes up with the parent's own pgid, and a `kill -KILL` to that group
  takes both — which is what launchd does to a job and what Ctrl-C does in `just daemon`. A signal
  sent to the daemon's **pid alone** leaks it: the parent dies before `stop` runs and the child
  goes on advertising an address nothing answers, until the next start registers over it.
- **The token is never advertised**, and a test asserts it against the secret itself rather than
  against the word "token". mDNS is an unauthenticated broadcast to the whole network, and that
  token is the only thing in front of every route but `/health`.
- **A missing `dns-sd` is a log line.** Nothing here may keep the daemon from starting, and a
  hand on Linux has no such binary — though a hand never reaches this lifespan anyway, since
  `--hand` builds `fleet/hand.py`'s own app.

## Off the home network

`https://deckhand.jurrejan.com` — the NAS Caddy, reverse-proxying the M2's `192.168.178.180:4180`.
Added with `cdy` (`~/dev/node/caddyctl`); the site file is
`/share/CACHEDEV1_DATA/Container/caddy/etc/sites/deckhand.caddy` and `cdy edit deckhand` is how it
changes, because every mutation there is snapshot → validate-in-container → reload → rollback.

**Nothing about the daemon changed.** It still binds `0.0.0.0:4180`, still answers the LAN, still
takes the one `x-deckhand-token`. The edge is in front of it, not instead of it:

- **Caddy checks the same header the daemon does.** One secret, and the app needed no change for
  it — `request()` already sets the token on every call, `/health` included. The literal lives in
  that site file the way `fin.caddy`'s bearer does, so rotating the daemon's token means editing
  it there in the same breath or the phone stops connecting from outside.
- **Gated in front, because of what this is.** Deckhand can put words into a running Claude
  session on three machines, start new ones and move the phone's screen. `/health` alone is open
  on the LAN and says whether the person is at the keyboard. None of that should be answering an
  internet scanner, so nothing unpaired reaches the Mac at all.
- **No token at all answers 404, a wrong one answers 401.** A scanner learns only what every
  unpublished hostname on that Caddy tells it; a person who mistyped the pairing code reads
  "unauthorized" in the app, which is what `DeckhandError` makes of 401 where it makes "not live"
  of 404. The bit that gives away is only reachable by already having sent a token.
- **The IP is a literal, and a DHCP reservation is what holds it still.** It drifted `.145` →
  `.180` once, before the router was given `6c:7e:67:d2:08:34 → 192.168.178.180`. The Caddy
  container cannot resolve `m2-2.local` (no mDNS in there — measured), so a literal is the only
  shape available; lose that reservation and this is the line that breaks, along with every other
  M2-hosted vhost on that Caddy, which all carry the same one.

In the app it is just the Address field: `https://deckhand.jurrejan.com`, token unchanged.
`ServerSettings.baseURL` deliberately does not pin `:4180` onto an `https` host — that host is
Caddy on 443 — while anything spoken over http still means this Mac's daemon. Hairpin NAT means
the public URL resolves and works on the LAN too, so one setting covers both places; the LAN name
is still worth keeping for the hop it saves.

## Verification

`just daemon-lint` (ruff) and `just daemon-test` (pytest), both inside `just check`.
`docs/commands.md` is generated (`just commands-doc`);
`tests/mcp/test_commands_doc.py` fails when it drifts.
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
