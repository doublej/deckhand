# Commands

> Every HTTP route, MCP tool and `deckhand` command: what each takes, what it answers, how it
> fails, and what the agent surface refuses on purpose

The tables between `<!-- generated:… -->` markers are written from the code by
`daemon/tools/commands_doc.py` — the app's route table and docstrings, the MCP server's own tool
list, and the command's `COMMANDS`, `ERRORS` and `NO` tables. Edit the prose; never the tables.
`tests/mcp/test_commands_doc.py` fails the moment the code and this page disagree. Regenerate:

```bash
uv run --directory daemon python tools/commands_doc.py
```

## Three surfaces, one daemon

- **The HTTP API** — FastAPI on port 4180, `daemon/src/deckhand_daemon/app.py` and every
  `routes.py` under it. The phone, the headset, the Mac app and utt's page all speak it, and it is
  the whole surface: everything the person can do from any of them is a route. Every route but
  `/health` needs the `x-deckhand-token` header. Off the home network the same surface is
  `https://deckhand.jurrejan.com`, behind the same header.
- **The MCP server** — `deckhand-mcp`, over stdio, installed once with `just install-mcp`. Twelve
  tools for the agent *inside* a session. Nine of them are routes, called over the loopback with
  the token, so the filter chain, the standing orders, the delivery record and a folder's refusal
  to be interrupted all still apply. `ask_on_phone` and `read_answer` run the skill's own slip
  scripts; `whoami` reads the session's own record. The server finds its session by walking up to
  the `claude` process, never from its working directory.
- **The `deckhand` command** — `daemon/src/deckhand_daemon/mcp/cli.py`, on PATH with
  `just install-cli`. The same twelve tools as one shell command, for a session without the MCP
  server, or a person at a terminal. JSON when piped, Markdown-ish text on a terminal, a structured
  error on stderr and an exit status per category. `deckhand` alone is a status line;
  `deckhand prime` (`--json` for the model) is the whole contract, and prints this page's path.

The agent surface is a strict subset of the API, and the subset is an authority decision. A
capability on the API with no tool and no command is either under *Refused on purpose* below, or
one an agent does not need.

## The authority line

- **The route is an authority choice, not a transport choice.** The keyboard route types into a
  pane and arrives as the person at the machine. The peer socket arrives labelled as another
  Claude session, carrying none of the person's authority. An agent speaks only down the socket:
  `say_to_session` and `deckhand say` take no route argument, and refuse a Codex thread, whose
  only way in carries the person's authority.
- **Nothing on the agent surface stops, compacts, clears, closes or renames a session, or
  answers a slip.** Input into a Mac window is the person's hand and is never an agent tool. An
  agent never closes a session — a session's plane comes from the listing and is never kept in
  the space, so `close_plane` has nothing to name one by.
- **What an agent may do in the headset:** open and close web and window planes, which are
  furniture — opening one starts no process and closing one stops nothing — and start a session
  beside itself through `POST /space/sessions`, which only starts in a folder the project list
  names and Claude Code already trusts. It starts with no task; the agent briefs it with `say`.
- **`by` says who did it.** A plane an agent opens or closes carries the agent's name; no `by` is
  the person. When the person opens a page beside a session, hands it to another, moves it away or
  closes it, the session it concerns is told, down its socket, in the daemon's own voice
  (`prompts/space-given.md`, `prompts/space-taken.md`). What an agent did itself is not news to it.
- **None of this is a fence.** One token serves the phone and every agent, it is a file the
  agent can read, and `curl` performs anything a tool declines. The refusals are absence, written
  down with a reason so an agent stops looking instead of going around them. The agent token in
  `docs/agent-surface.md` is what would make them real.

## Common workflows

**Ask the person something.** Where they are decides how.

```bash
deckhand presence                                    # laptop or headset: ask in the conversation
deckhand ask "Ship it?" --option Ship --option Wait  # phone: a slip; prints its id
deckhand answer ship-it                              # exit 4 until answered
```

The daemon also messages the session the moment an answer lands, so there is no need to poll.

**Tell them a long job finished.** `deckhand notify "Migration done, tests green"`. Exit 4 means
the folder refuses interruptions and the person has *not* seen it: say so in the conversation.

**Hand work to another session.**

```bash
deckhand start ../other-repo                          # beside you in the headset
deckhand say other-repo "Port the reader, then message me what changed"
```

It answers down your own inbox with Claude Code's `SendMessage`; nothing here reads its
conversation for you.

**Put a page beside you in the headset.**

```bash
deckhand open https://shop.atlas.local.jurrejan.com/  # a retry hands back the same plane
deckhand space                                        # around_you: what stands with you
deckhand close 3f2a                                   # by id prefix; closed as you, nobody told
```

The headset is another machine: prefer the project's atlas hostname over `localhost`, which is
rewritten to this Mac's LAN address and only answers if the server binds `0.0.0.0`.

**With neither the tool nor the command**, the same calls go over HTTP:

```bash
curl -s -X POST "http://127.0.0.1:4180/sessions/$CLAUDE_CODE_SESSION_ID/notify" \
  -H "x-deckhand-token: $(cat ~/Library/Application\ Support/Deckhand/token)" \
  -H 'content-type: application/json' -d '{"line":"Migration done, tests green."}'
```

## One capability, three doors

Each command is one MCP tool, and each tool is the route or script it reaches.

<!-- generated:parity -->
| Command | MCP tool | Reaches | Reads only |
|---|---|---|---|
| `deckhand presence` | `presence` | `GET /presence` | yes |
| `deckhand whoami` | `whoami` | this session's own record | yes |
| `deckhand sessions` | `sessions` | `GET /sessions` | yes |
| `deckhand ask` | `ask_on_phone` | `skills/deckhand/scripts/slip.py` | no |
| `deckhand answer` | `read_answer` | `skills/deckhand/scripts/answer.py` | yes |
| `deckhand notify` | `call_for_attention` | `POST /sessions/{id}/notify` | no |
| `deckhand say` | `say_to_session` | `GET /sessions`, `GET /manager/session`, `POST /sessions/{id}/say` | no |
| `deckhand end` | `ask_to_end` | `POST /end-requests` | no |
| `deckhand open` | `open_plane` | `POST /space/planes` | no |
| `deckhand space` | `space` | `GET /space`, `GET /sessions/{id}/space` | yes |
| `deckhand start` | `start_session` | `POST /space/sessions`, `GET /projects` | no |
| `deckhand close` | `close_plane` | `GET /space`, `DELETE /space/planes/{id}` | no |
| `deckhand windows` | `mac_windows` | `GET /windows` | yes |
| `deckhand tmux` | `tmux_tree` | `GET /sessions`, `tmux list-panes` | yes |
| `deckhand arrange` | `tmux_arrange` | `GET /sessions`, `tmux rename-window`, `tmux set-option`, `tmux move-window`, `tmux swap-window`, `tmux join-pane`, `tmux break-pane`, `tmux select-layout`, `tmux resize-pane`, `tmux select-window`, `tmux select-pane`, `tmux list-panes` | no |
<!-- /generated:parity -->

Two things need neither a tool nor a command, because they are files in the session's own folder:
a logbook for a long job (`skills/deckhand/scripts/logbook.py`) and a hand-written slip
(`skills/deckhand/templates/`). Reading another session's conversation (`GET
/sessions/{id}/turns`) is safe and deliberately not a tool: a session you briefed answers you down
your inbox, and its transcript is a file you can `Read`.

## Refused on purpose

What an agent might reach for and will not find. `deckhand <verb>` for any of these answers
`PERSON_ONLY` with the reason, and the MCP server's instructions carry the same list. All of it is
one table, `daemon/src/deckhand_daemon/mcp/refused.py`.

<!-- generated:refused -->
| Verbs | What does it for the person | Why no tool or command |
|---|---|---|
| `cancel`, `stop`, `compact`, `clear`, `exit`, `kill` | `POST /sessions/{id}/control` | keystrokes the person presses on a session's own pane. `clear` cannot be undone, and closing a session is theirs alone: `ask_to_end` asks them, and only their Allow ends one |
| `rename` | `POST /sessions/{id}/name` | it types `/rename` into the pane, which is the keyboard route and arrives as the person |
| `type`, `keyboard` | `POST /sessions/{id}/say?route=keyboard` | the keyboard route arrives as the person at the machine; `say` goes down the socket labelled as an agent, and is the only way an agent speaks to a session |
| `respond`, `reply` | `POST /sessions/{id}/artifacts/{aid}/answer` | a slip is answered by the person; an agent answering one is asking and answering itself |
| `click`, `input` | `POST /windows/{id}/input` | it drives the Mac's real cursor and keyboard, which is the person's hand |
| `settings`, `filters`, `orders` | `PUT /settings, PUT /sessions/{id}/filters, PUT /sessions/{id}/orders` | what this Mac and a session are set to do is the person's; an agent that can rewrite a filter chain can remove the filter that would have stopped it |
| `pair`, `devices`, `forget` | `POST /pair/open, DELETE /devices/{id}` | pairing hands a device everything this Mac's token can do, so it is opened by the person standing at the Mac (`just pair`), never on someone's behalf |
| `send-keys`, `kill-pane`, `kill-window`, `respawn` | `tmux send-keys, kill-pane, kill-window, respawn-pane` | typing into a pane is the keyboard route, and killing or respawning one ends the session in it — the person's own press. `tmux_arrange` moves panes, never into them |
| `manager` | `POST /manager/say` | it speaks into the manager's conversation as the person. The manager is a session too: `say_to_session manager`, or Claude Code's own SendMessage to `deckhand-manager`, reaches it as an agent |
<!-- /generated:refused -->

## The `deckhand` command

`deckhand` alone prints this session, its folder, where the person is and whether the daemon
answers. `deckhand prime` prints the contract as Markdown, `deckhand prime --json` as JSON. Every
command takes `--json`; `-` for a question, line or text reads it from stdin.

<!-- generated:cli -->
| Command | Arguments | MCP tool | Fails with | Does |
|---|---|---|---|---|
| `deckhand presence` | `[--json]` | `presence` | `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED` | where the person is: `laptop`, `headset` or `phone`, one word; --json adds idle seconds, screen lock and when the phone was last heard from |
| `deckhand whoami` | — | `whoami` | `NO_SESSION` | this session's id, name and folder |
| `deckhand sessions` | `[--fields name,status] [--limit 50]` | `sessions` | `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED` | every live session on this Mac, with how many slips each has waiting |
| `deckhand ask` | `QUESTION\|- [--kind confirm\|pick\|text\|aloud] [--option LABEL]... [--note TEXT] [--question id:text]... [--action TEXT] [--expires-hours H] [--key ID]` | `ask_on_phone` | `BAD_KIND`, `REFUSED` | put a slip on the phone; answers with its id. confirm: two --option, yes then no, and --action. pick: one --option per choice. text: --option is the field label. aloud: --question per spoken answer. Then end the turn: a decision's answer arrives |
| `deckhand answer` | `ID [--wait SECONDS]` | `read_answer` | `NO_SUCH_SLIP`, `PENDING` | the answer, `verified` if their phone signed it; exit 4 while none. --wait max 600 |
| `deckhand notify` | `LINE\|-` | `call_for_attention` | `BAD_ANSWER`, `DAEMON_DOWN`, `NO_SESSION`, `REFUSED`, `NOT_PUSHED` | a Lock Screen card asking for the person; exit 4 when the folder refuses |
| `deckhand say` | `SESSION TEXT\|-` | `say_to_session` | `BAD_ANSWER`, `CODEX_THREAD`, `DAEMON_DOWN`, `NO_SUCH_SESSION`, `REFUSED`, `NOT_DELIVERED` | message another session down its inbox, as an agent — `manager` is the manager; exit 4 when it was not said |
| `deckhand end` | `SESSION... --why TEXT` | `ask_to_end` | `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED` | ask the person, on their phone, to end these sessions on any machine; ends nothing itself — only their Allow does |
| `deckhand open` | `[URL] [--window ID] [--title TEXT]` | `open_plane` | `BAD_ANSWER`, `BAD_PLANE`, `DAEMON_DOWN`, `REFUSED` | put a web page, or a Mac window by id, beside this session in the person's headset; the URL must be reachable from the headset on the LAN |
| `deckhand space` | `[--full]` | `space` | `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED` | where this session is in the headset, what is beside it, and every page and window open; --full adds every kept pose |
| `deckhand start` | `[FOLDER] [--provider claude\|codex\|opencode]` | `start_session` | `BAD_ANSWER`, `DAEMON_DOWN`, `NOT_STARTABLE`, `NO_SESSION`, `REFUSED` | start a session beside this one in the headset; brief it with `say` |
| `deckhand close` | `ID\|PREFIX` | `close_plane` | `BAD_ANSWER`, `DAEMON_DOWN`, `NO_SUCH_PLANE`, `REFUSED` | close a plane by its id or a unique prefix — a page or a window, never a session |
| `deckhand windows` | — | `mac_windows` | `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED` | this Mac's windows, with the ids `open --window` takes |
| `deckhand tmux` | — | `tmux_tree` | `BAD_ANSWER`, `DAEMON_DOWN`, `NO_TMUX`, `REFUSED` | every tmux session, window and pane, with the Claude session in each; `you` is this one's pane |
| `deckhand arrange` | `ACTION TARGET [--to TARGET] [--name TEXT] [--layout LAYOUT] [--split right\|below]` | `tmux_arrange` | `BAD_ANSWER`, `BAD_ARRANGE`, `DAEMON_DOWN`, `NO_SUCH_TARGET`, `NO_TMUX`, `REFUSED`, `TMUX_REFUSED` | move tmux's furniture: rename, group, ungroup, move, swap, join, break, layout, zoom, focus. TARGET is a session name, %pane, @window, session:index or window name |

| Exit | Categories |
|---|---|
| 0 | ok |
| 1 | user_error, upstream, internal |
| 2 | usage |
| 3 | transient |
| 4 | negative |

| Code | Category | Retryable | Hint |
|---|---|---|---|
| `NO_SESSION` | user_error | no | run it from a Claude Code session's Bash tool: it finds its session by walking up to the `claude` process |
| `DAEMON_DOWN` | transient | yes | start it: `launchctl kickstart -k gui/$(id -u)/com.jurrejan.deckhand`, or `just daemon` in the deckhand repo |
| `REFUSED` | upstream | no | the daemon's own words are in `message` |
| `BAD_ANSWER` | internal | yes | read the daemon's log: `just logs` in the deckhand repo |
| `BAD_KIND` | user_error | no | --kind is one of confirm, pick, text, aloud |
| `BAD_PLANE` | user_error | no | a URL or --window ID, not both and not neither; `deckhand windows` lists the ids |
| `NO_SUCH_SESSION` | user_error | no | `deckhand sessions` lists the names; a unique id prefix or part of a name is enough |
| `CODEX_THREAD` | user_error | no | a Codex thread only takes the person's own words; ask the person instead |
| `NOT_DELIVERED` | negative | no | it was not said — `message` says why; a filter on that session may have stopped it |
| `NOT_PUSHED` | negative | no | the person has not seen it: this folder refuses interruptions — say it in the conversation instead |
| `PENDING` | negative | yes | no answer yet; the daemon messages this session when one lands, or block on it: `deckhand answer <id> --wait 300` |
| `NO_SUCH_SLIP` | user_error | no | no slip has that id in this session's folder: the id is what `deckhand ask` printed |
| `NO_SUCH_PLANE` | user_error | no | `message` lists the planes open, by id prefix; `deckhand space` shows them whole |
| `NOT_STARTABLE` | user_error | no | `message` says why and lists folders a session can start in, nearest first; pass one to `deckhand start` |
| `NO_TMUX` | user_error | no | no tmux server answers here: this session is not in tmux |
| `NO_SUCH_TARGET` | user_error | no | `deckhand tmux` lists every pane and window; a session name, %pane, @window, session:index or window name |
| `BAD_ARRANGE` | user_error | no | rename and group need --name, move, swap and join need --to, layout needs --layout |
| `TMUX_REFUSED` | upstream | no | tmux's own words are in `message` |
| `PERSON_ONLY` | user_error | no | refused on purpose, not missing: it is the person's own. Ask them — `deckhand presence` says where — rather than going around it with curl |
| `USAGE` | usage | no | `deckhand prime` lists every command and its arguments |
<!-- /generated:cli -->

## The MCP tools

The arguments are the tool's own JSON schema. A tool never raises: a failure comes back as
`{error, code}`, and a "no" as a field — `went`, `pushed`, `answered` — that the command turns
into exit 4.

<!-- generated:mcp -->
### `tmux_tree` — reads only

Arguments: —  
Reaches: `GET /sessions`, `tmux list-panes`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `NO_TMUX`, `REFUSED`

The person's whole tmux, to organise it with `tmux_arrange`: every tmux session, its
windows (id, index, name, `group`, active, zoomed) and their panes (id, size, the command
running, its folder, and the Claude session in it by name, id and status). `you` is the pane
this session is in.

### `tmux_arrange` — writes

Arguments: `action`: rename|group|ungroup|move|swap|join|break|layout|zoom|focus, `target`: string, `to`: string = null, `name`: string = null, `layout`: string = null, `split`: right|below = "right"  
Reaches: `GET /sessions`, `tmux rename-window`, `tmux set-option`, `tmux move-window`, `tmux swap-window`, `tmux join-pane`, `tmux break-pane`, `tmux select-layout`, `tmux resize-pane`, `tmux select-window`, `tmux select-pane`, `tmux list-panes`  
Fails with: `BAD_ANSWER`, `BAD_ARRANGE`, `DAEMON_DOWN`, `NO_SUCH_TARGET`, `NO_TMUX`, `REFUSED`, `TMUX_REFUSED`

Move the person's tmux furniture, never what runs in it. `target`/`to`: a Claude session
name or id, `%3`, `@2`, `session:index`, `session:name` or a window name (`tmux_tree`).

`rename`/`group` the window as `name` (the headset follows groups); `ungroup`. `move` it
after `to`'s, or to the end of tmux session `to`; `swap` with `to`'s. `join` the pane into
`to`'s window, `split` right or below; `break` it into its own window (`name`). `layout`:
tiled, even-horizontal, even-vertical, main-horizontal, main-vertical. `zoom` toggles.
`focus` moves the person's view: only when asked.

Nothing here types into a pane or closes one; those are the person's.

### `whoami` — reads only

Arguments: —  
Reaches: this session's own record  
Fails with: `NO_SESSION`

Which session this is: its id, its name, the folder it is working in.

### `ask_on_phone` — writes

Arguments: `question`: string, `kind`: confirm|pick|text|aloud = "confirm", `options`: string[] = null, `note`: string = "", `questions`: string[] = null, `action`: string = "", `expires_hours`: number = 24.0, `key`: string = ""  
Reaches: `skills/deckhand/scripts/slip.py`  
Fails with: `BAD_KIND`, `REFUSED`

Ask the person on their phone. Returns the slip's id. **Then end your turn.**

Confirm, pick and text are **decisions**: signed by the phone and typed into this session as
`Decision <id> — "<question>": <choice>. This covers exactly: <action>.` Do not poll
`read_answer`; act on that message, and only on what it covers.

`kind`: confirm, pick, text or aloud. `question`: under 80 chars; detail in `note`.
`action`: required for confirm, exactly what a yes allows, one line. `options`: yes/no
labels (confirm), choices (pick), field label (text). `questions`: aloud only, `id:text`,
spoken; not a decision. `expires_hours`: default 24. `key`: the id; re-asking an answered
decision returns its answer.

### `read_answer` — reads only

Arguments: `id`: string, `wait_seconds`: number = 0.0  
Reaches: `skills/deckhand/scripts/answer.py`  
Fails with: `NO_SUCH_SLIP`

What the person answered on a slip, if they have, and whether their phone proved it.

`verified` is true only for a decision answered with the phone's signature over this very
page; a file written by hand, or any non-decision slip, reads false. `device` and
`fingerprint` say which phone. `wait_seconds` blocks for up to ten minutes; left out it looks
once, which is usually right because the daemon types a decision's answer into this session.

### `presence` — reads only

Arguments: —  
Reaches: `GET /presence`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED`

Where the person is right now. `where` is `laptop` — at this Mac, reading this
conversation, so ask here — `headset`, reading it on a pane in the headset, so ask here too —
or `phone`: away from it, so `ask_on_phone`, or `call_for_attention` for something they must
see. Ask again before each question; it moves
the moment they sit down or walk off.

### `call_for_attention` — writes

Arguments: `line`: string  
Reaches: `POST /sessions/{id}/notify`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `NO_SESSION`, `REFUSED`

Ask for the person outright, in your own words — a card on their Lock Screen.

For when a long job has finished with nobody watching or this session is stuck. The folder may
refuse to be interrupted, and the refusal comes back as `pushed: false` with the reason: say so
rather than carrying on as though they have seen it.

### `sessions` — reads only

Arguments: —  
Reaches: `GET /sessions`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED`

Every session live on this Mac — Claude Code, Codex or OpenCode: its name, folder,
whether it is busy, how many slips it has left waiting for the person, and its `provider`. A
`codex` thread is listed but takes no agent's words, so `say_to_session` refuses it; an
`opencode` session takes them, labelled as not from its user.

### `say_to_session` — writes

Arguments: `session`: string, `text`: string  
Reaches: `GET /sessions`, `GET /manager/session`, `POST /sessions/{id}/say`  
Fails with: `BAD_ANSWER`, `CODEX_THREAD`, `DAEMON_DOWN`, `NO_SUCH_SESSION`, `REFUSED`

Say something to another session on this Mac, by name or by id — `manager` is the
manager, the agent behind the person's phone panel.

It arrives down that session's peer inbox — or, for an OpenCode session, as OpenCode's
synthetic input — labelled as coming from another agent and carrying none of your user's
authority, which is the only way an agent may speak to one. It
can be stopped by that session's filters, so read the receipt: `went: false` means it was not
said, whatever the reason beside it. Nothing comes back down this tool: the manager answers
in its panel, so say who you are and, if you need a reply, how to reach you.

### `ask_to_end` — writes

Arguments: `names`: string[], `why`: string  
Reaches: `POST /end-requests`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED`

Ask the person to end sessions — on any machine, by name or id — with one Allow/Deny alert
on their phone naming each one and your `why`. **This ends nothing.** Their Allow ends them,
by SIGTERM to each process on its own machine; Deny or no tap and nothing happens, and
nothing tells you which: look at `sessions` later rather than waiting on it.

For cleanup the person asked for, with the sessions you judged idle or orphaned. Refused
unless each name is exactly one Claude session with a process. Returns the alert's `id`.

### `open_plane` — writes

Arguments: `url`: string = null, `window`: integer = null, `title`: string = null  
Reaches: `POST /space/planes`  
Fails with: `BAD_ANSWER`, `BAD_PLANE`, `DAEMON_DOWN`, `REFUSED`

Open a web page, or one of this Mac's windows, as a plane beside this session in the
person's headset. Give exactly one: `url`, or `window` — an id from `mac_windows`.

The headset is another machine on the LAN, so the URL has to be reachable from there. Prefer
the project's atlas dev hostname, `https://<slug>.atlas.local.jurrejan.com`. A localhost URL
is rewritten to this Mac's LAN address, which only works if the server binds 0.0.0.0. A Mac
window plane is view-only: the person sees it and cannot click into it.

What the person says while looking at the plane comes to this session. Returns the plane; its
`id` is what `close_plane` takes. Opening what is already open beside you hands back that
plane with `reused: true` rather than a second copy, so a retry is safe.

### `space` — reads only

Arguments: `full`: boolean = false  
Reaches: `GET /space`, `GET /sessions/{id}/space`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED`

Where you are in the person's headset and what is around you. `around_you` is your pose,
your group, and every session, page and window `beside` you — in your group or opened near
you. `planes` is every page and window open: id, kind, url or window, title, the session it is
`near` and who opened it (`by` null is the person). `full` adds every kept pose, which is
room coordinates and rarely what you need.

### `start_session` — writes

Arguments: `folder`: string = null, `provider`: claude|codex|opencode = "claude"  
Reaches: `POST /space/sessions`, `GET /projects`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `NOT_STARTABLE`, `NO_SESSION`, `REFUSED`

Start another Claude Code session, standing beside you in the person's headset in your
group — to hand it part of the work, or to show the person something running. `folder`
defaults to your own; it must be a project the Mac lists and Claude Code already trusts, or
the answer says why not. It starts with no task: tell it what to do with `say_to_session`,
which reaches it as an agent. You cannot close it afterwards — that is the person's.

### `close_plane` — writes

Arguments: `id`: string  
Reaches: `GET /space`, `DELETE /space/planes/{id}`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `NO_SUCH_PLANE`, `REFUSED`

Close a plane in the person's headset, by the id `open_plane` or `space` gave — a unique
prefix of it is enough. Only a web page or a Mac window: an agent can never close a session,
and nothing here names one. Closed as you, so the session it stood beside is not told the
person took it away.

### `mac_windows` — reads only

Arguments: —  
Reaches: `GET /windows`  
Fails with: `BAD_ANSWER`, `DAEMON_DOWN`, `REFUSED`

This Mac's windows, each with the `id` `open_plane` takes, its app, title and size. Says
why when the window helper is not running.
<!-- /generated:mcp -->

## The HTTP API

Grouped by router. *Errors* are what a route's own body raises, 401 for a missing or wrong token,
404 where it looks a session up, and 422 for a parameter FastAPI cannot read; a refusal raised
inside a helper is not listed, so treat the column as the least a route can answer. Every error is
`{"detail": "…"}` in the daemon's own words. The shapes the routes answer with are in
`CLAUDE.md` under *The wire*, `docs/space.md`, and `skills/deckhand/reference/wire.md`.

<!-- generated:http -->
### addresses

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /sessions/{session_id}/addresses` | — | 200 | 401, 422 | Every URL, IP and domain the session and its subagents wrote: checked, ranked, matched to atlas. |

### artifacts

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /sessions/{session_id}/artifacts` | — | 200 | 401, 404, 422 | What this project is currently asking, and which of it has been answered. |
| `GET /sessions/{session_id}/artifacts/{artifact_id}` | — | 200 | 401, 404, 422 | The page, as HTML. The app injects the tokens and the policy around it; this only serves. |
| `GET /sessions/{session_id}/artifacts/{artifact_id}/answer` | — | 200 | 401, 404, 422 | What was answered last time. `{"value": null}` when nobody has, which is not an error. |
| `POST /sessions/{session_id}/artifacts/{artifact_id}/answer` | `?route`: string (auto, keyboard or socket; not a decision), body `{value?, proof?}` | 200 | 401, 404, 422 | Take the answer, write it down, then tell the session — in that order, and it matters. |

### bindings

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /bindings/match` | `?url`: string | 200 | 401, 422 | The bindings a page belongs to, best first: longest prefix, then most recently used. |
| `GET /bindings` | — | 200 | 401 | Every web page pinned to a project folder, as an origin plus an optional path prefix. |
| `POST /bindings` | body: JSON object | 200 | 401, 422 | Idempotent on (normalised pattern, path), and creating one counts as using it. |
| `DELETE /bindings` | `?pattern`: string, `?path`: string | 200 | 401, 422 | Unpin one page from one folder, by the pattern and path it was pinned with: `{removed}`. |
| `POST /feedback` | body: JSON object | 200 | 400, 401, 422 | Keep one thing said about one spot on a page, stamped here, under its folder. |
| `GET /feedback` | `?path`: string | 200 | 401, 422 | What was said about spots on that folder's pages, oldest first: `{entries}`. |
| `GET /feedback/image` | `?id`: string, `?kind`: string | 200 | 400, 401, 404, 422 | An entry's screenshot or crop. Found by the kept entry's id, never by a path sent here. |
| `PUT /feedback/crop` | body: JSON object | 200 | 401, 404, 422 | Keep the crop of an entry's screenshot the person drew, replacing any before it. |

### filters

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /filters` | — | 200 | 401 | Everything this daemon can do to a prompt. No chain: a chain belongs to a terminal. |
| `GET /sessions/{session_id}/filters` | — | 200 | 401, 404, 422 | What this terminal runs, and what it could run, in the one call a settings screen needs. |
| `PUT /sessions/{session_id}/filters` | body `{steps}` | 200 | 400, 401, 404, 422 | Replace this terminal's chain. List order is run order, and a filter may appear twice. |

### tray

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /tray` | `?since`: integer = 0 (the last update id this phone has seen) | 200 | 401, 422 | Everything open on every machine, newest first, and every update after the cursor. |

### links

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /sessions/links` | `?within`: number = 300.0 (how many seconds back to look for messages between sessions) | 200 | 401, 422 | Which sessions have messaged which, lately. Both ends are always on the listing. |

### manager

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /manager` | `?since`: integer = 0 (the last entry id this phone has seen), `?watching`: boolean = true (false for a poll with no panel on screen) | 200 | 401, 422 | What has been said, after the id the phone already has, and whether more is coming. |
| `GET /manager/session` | — | 200 | 401, 404 | The manager's own live session, so an agent can say something to it down its inbox as to any other (`say_to_session`) — labelled as an agent, never as `/manager/say`'s person. 404 while the daemon holds none open. Newest first, should a second daemon be holding one too. |
| `POST /manager/away` | — | 204 | 401 | The panel went off screen. Everything the manager says from here is pushed. |
| `POST /manager/say` | body `{text, viewing?, viewing_name?}` | 201 | 400, 401, 422 | Say something to the manager. Answers with the entry, not with the reply. |
| `POST /manager/audio` | `?say`: boolean = true (false to transcribe only, for the review card), `?viewing`: string = "" (the session on screen behind the panel), `?viewing_name`: string = "" (that session's name), form `{file}` | 201 | 400, 401, 413, 415, 422 | A clip for the manager: utt turns it into text and the manager is asked with it. |
| `POST /manager/clear` | — | 200 | 401 | Start over. The entries go and so does the thread behind them — see `talk.clear`. |
| `POST /manager/tools/{name}` | body: JSON object | 200 | 401, 404, 422 | One of the manager's tools, run in this process — where the fleet's links and the conversation file already live — and answered as the text the tool said. |

### orders

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /sessions/{session_id}/orders` | — | 200 | 401, 404, 422 | What this session is being reminded of on every message. Empty when it has never been told. |
| `PUT /sessions/{session_id}/orders` | body `{text}` | 200 | 401, 404, 422 | Replace them, and answer with what was stored — which is what will actually be carried. |

### agents

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /sessions/{session_id}/agents` | — | 200 | 401, 422 | Every subagent this session has started, newest first, and whether each is still going. |
| `GET /sessions/{session_id}/agents/{agent_id}/turns` | `?limit`: integer = 8, `?before`: integer = 0 (how many turns from the end to skip) | 200 | 401, 422 | One subagent's own conversation, paged exactly as the session's is. |

### core

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /presence` | — | 200 | 401 | `where` is `laptop`, `phone` or `headset`: where a session should reach the person. |
| `POST /presence/phone` | — | 204 | 401, 403, 422 | The person just touched the app. It says so at most every ten seconds and on coming to the front, and from then until a key is pressed at the Mac, `where` is `phone`. |
| `POST /presence/headset` | — | 204 | 401 | The headset is being worn: it beats every ten seconds while it is, and for `HEADSET_LIVE` after the last beat `where` is `headset`. |
| `GET /sessions/{session_id}/header` | — | 200 | 401, 404, 422 | The picture itself. 404 is "this project has none", which the phone draws as nothing. |
| `POST /pair/open` | — | 200 | 401 | A six-digit code, good once for `window.LASTS` seconds; replaces any code already open. |
| `POST /pair/transcribe` | `?name`: string = "browser" | 200 | 401, 422 | A token that can call `POST /transcribe` and nothing else, for a web page's mic button. Minted here rather than paired: the person at the Mac asks for it, so there is no code. |
| `POST /pair/manager` | `?name`: string = "mcp" | 200 | 401, 422 | A token that can reach `/mcp`, the manager's tools, and nothing else — for an MCP client off this Mac. Minted like the transcribe one: the person at the Mac asks for it. |
| `POST /pair` | body `{code, name?, kind?}` | 200 | 422 | Trade the code on the Mac's screen for a token of this device's own. |
| `GET /pair/check` | — | 200 | 401 | 200 for any token this Mac accepts, 401 for anything else. For the NAS Caddy's `forward_auth`, so a device token works off the home network without the edge holding a literal of its own. |
| `GET /devices` | — | 200 | 401 | Every device paired with a code: id, name, kind, when it paired, when it was last heard. |
| `PUT /devices/key` | body `{publicKey}` | 200 | 400, 401, 409, 422 | The phone's public signing key, filed on its own row. First key wins. |
| `GET /devices/key` | — | 200 | 401 | Whether the calling device has filed a key, and its fingerprint. |
| `DELETE /devices/{device_id}` | — | 204 | 401, 404, 422 | Take one device's token away. It stops working on its next request; no other changes. |
| `GET /health` | — | 200 | — | Open on purpose: the app pings it to tell 'wrong host' from 'wrong token'. |
| `POST /transcribe` | form `{file}` | 200 | 400, 401, 413, 415, 422 | A clip in, its words out. No session, no delivery, and the clip is not kept. |
| `GET /sessions` | — | 200 | 401 | — |
| `GET /machines` | — | 200 | 401 | Every machine on the network and whether it is reachable right now. |
| `GET /sessions/all` | — | 200 | 401 | The whole network's sessions in one answer, newest first. |
| `GET /sessions/{session_id}/summary` | — | 200 | 401, 404, 422 | The last briefing written for this session, and this session to the front of the queue. |
| `GET /briefings` | — | 200 | 401 | Every live session's last briefing, off disk, in one call. |
| `GET /sessions/{session_id}/files` | — | 200 | 401, 404, 422 | Everything this session touched that a person could open and look at. |
| `GET /sessions/{session_id}/file` | `?path`: string (one of /files) | 200 | 401, 404, 413, 422 | One of those files, by the path the listing gave. |
| `GET /sessions/{session_id}/turns` | `?limit`: integer = 8, `?before`: integer = 0 (how many turns from the end to skip) | 200 | 401, 404, 422 | A page of the conversation, newest page first. |
| `GET /sessions/{session_id}/context` | — | 200 | 401, 404, 422 | Every CLAUDE.md a session in this folder is loaded with, as a tree. |
| `GET /sessions/{session_id}/raw` | `?limit`: integer = 1500 | 200 | 401, 404, 422 | Everything in the transcript, in order, without the syntax it is stored in. |
| `POST /sessions/{session_id}/queue/clear` | — | 200 | 401, 404, 422 | Draw a line under this session's inbox: whatever the lane still shows was never read. |
| `POST /sessions/{session_id}/focus` | — | 200 | 401, 404, 409, 422 | — |
| `GET /sessions/{session_id}/commands` | — | 200 | 401, 404, 422 | The slash commands and skills this session could be handed by name. |
| `POST /sessions/{session_id}/control` | `?action`: string (cancel, compact, clear or exit) | 200 | 400, 401, 404, 409, 422 | The four things you do to a session rather than say to it. |
| `POST /sessions/{session_id}/name` | body `{name}` | 200 | 401, 404, 409, 422 | Give a session a new display name, by running Claude Code's own `/rename` in its pane. |

### alerts

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /alerts` | `?since`: integer = 0 (the last alert id this asker has seen) | 200 | 401, 422 | Every card announced after the id the asker has, and the newest id there is. |

### push

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `POST /live/token` | body `{token, kind, session?}` | 200 | 400, 401, 422 | The phone hands over what the Mac needs to reach its Lock Screen. |
| `POST /sessions/{session_id}/notify` | body `{line}` | 200 | 400, 401, 404, 422 | An agent asking for the person outright, in its own words. |
| `POST /notify` | — | 202 | 401 | A Lock Screen card with two buttons and no session, whose tap this Mac answers to a loopback caller. One alert instead, on a phone that cannot take a card yet. |
| `POST /notify/{notify_id}/answer` | body `{proof?}` | 200 | 401, 422 | The phone's tap, signed like a decision's answer with the session `notify` and the notify id as its slip, and the action id as its value. Calls back once: a second tap is answered from the first. 410 once the notify is a day old, 502 when the caller did not take it. |
| `POST /end-requests` | body `{sessions, why, asker?}` | 202 | 401, 422 | An agent asking the person to end sessions, on any machine, by name or id. Ends nothing: the person's signed Allow on the alert does (`end_requests.py`), through `/notify/{id}/answer`. |

### projects

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /projects` | — | 200 | 401 | Every project on every machine, most recently touched first, and where the list came from. |
| `POST /projects/session` | body `{path, provider?}` | 200 | 400, 401, 409, 422 | Open a terminal in that folder and start Claude Code in it, wherever that folder is. |
| `GET /projects/commands` | `?path`: string | 200 | 401, 422 | The `just` recipes that folder offers, for the phone to run one directly — a deploy, a server, anything else the project's own justfile knows how to do. |
| `POST /projects/commands/run` | body `{path, recipe}` | 200 | 400, 401, 422 | Start that recipe in that folder. Refused unless it is one `/projects/commands` just listed — never a name the phone typed itself, which is the difference between running a button and running a string. |
| `POST /projects/commands/stop` | body `{path, recipe}` | 200 | 401, 422 | — |
| `GET /projects/commands/status` | `?path`: string, `?recipe`: string | 200 | 401, 422 | — |

### settings

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /settings` | — | 200 | 401 | What this Mac has been set to do, globally and per folder. |
| `PUT /settings` | body: JSON object | 200 | 401, 422 | What was stored, which is not always what was sent — see `wants.save`. |
| `GET /aliases` | — | 200 | 401 | Every word this Mac swaps on the way out of utt, as rows of two: heard, then meant. |
| `PUT /aliases` | body `{aliases}` | 200 | 401, 422 | Replace the list whole, the way `/settings` and `/filters` are written. |
| `GET /hints` | — | 200 | 401 | Every word utt is told to listen for in every clip — see `settings/hints.py`. |
| `PUT /hints` | body `{hints}` | 200 | 401, 422 | Replace the list whole, and answer with what was stored: blanks and repeats are dropped. |
| `GET /hints/folder` | `?path`: string | 200 | 401, 422 | Every list a session in `path` hears, outermost first — "" is the global one. |
| `PUT /hints/folder` | body `{path, hints}` | 200 | 401, 422 | Replace one layer's own words, and answer with what was stored. |
| `GET /settings/project` | `?path`: string | 200 | 401, 422 | What actually applies in one folder, already resolved. |
| `GET /sessions/{session_id}/folders` | — | 200 | 401, 404, 422 | The folders connected to this session's project, and the ones worth suggesting. |
| `PUT /sessions/{session_id}/folders` | body `{folders}` | 200 | 401, 404, 422 | Replace the project's folders whole — see `settings/folders.py`. Answers with what was kept: a relative path, the disk's root and the home folder itself are dropped. |

### space

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `GET /windows` | — | 200 | 401 | `[{id, app, title, w, h, cropped}]`: this Mac's windows, as `deckhand-windows` lists them. A 503 with the reason when that helper is not running. |
| `GET /windows/{window_id}/frame` | — | 200 | 401, 422 | One JPEG. The query (`whole=1`, …) is the helper's, as on the streams. |
| `POST /windows/{window_id}/input` | body: JSON object | 204 | 401, 422 | A click, drag, scroll or keystroke for that window, as the real cursor and keyboard. |
| `GET /windows/{window_id}/{kind}` | — | 200 | 401, 422 | `stream` is MJPEG, `hevc` the same window as HEVC access units off the Mac's hardware encoder. The query (`fps`, `max`, `q`, …) is the helper's to read and goes through whole — picking out `fps` alone is how the headset's `max` was once dropped on the floor here. |
| `GET /sessions/{session_id}/screen` | — | 200 | 401, 404, 409, 422 | `{lines, at, styled, runs?}`: the pane's rows, top to bottom, and when they were read. |
| `GET /terminal/theme` | — | 200 | 401 | `{font: {family, size}, fg, bg, bold, cursor, selection, ansi, lineSpacing, charSpacing, brightBold}`. Every pane draws the same, so a `?session=` the headset still sends changes nothing. |
| `GET /camera` | — | 200 | 401 | `{live, viewers, at}`: whether a picture came in the last two seconds, how many watch `/camera/stream` now, and when the last picture came (epoch seconds, null for none yet). |
| `POST /camera/frames` | — | 200 | 400, 401, 413 | One JPEG as the whole body → `{viewers}`. The headset's to call, once per picture, while someone watches or the person switched streaming on; `viewers` falling to 0 is its cue to stop unless they did. |
| `GET /camera/stream` | — | 200 | 401 | The camera as MJPEG (`multipart/x-mixed-replace; boundary=frame`), the last picture first. Watching is what asks the headset to stream: it counts in `viewers` until it disconnects. |
| `GET /space` | — | 200 | 401 | `{rev, planes, poses}`: every page and window open in the headset, and every kept pose. `rev` rises on every change, so a poller redraws only when it moved. |
| `POST /space/planes` | body: JSON object | 201 | 400, 401, 404, 422 | `{kind: web\|window, url?, window?, title?, near?, by?}` → the plane. `near` is a listed session or a 404; a loopback url becomes this Mac's LAN address. The same page already open beside the same session comes back with `reused: true` and a 200. No `by` is the person, and `near` is told. |
| `PUT /space/planes/{plane_id}/near` | body: JSON object | 204 | 401, 404, 422 | `{near}`: the person moved a page or window to another session's side, or to nobody's (`near` null). The headset's to call; the session it now belongs to is told, and so is the one it left. |
| `GET /sessions/{session_id}/space` | — | 200 | 401, 404, 422 | Where this session stands in the headset and what stands with it (`space/around.py`). |
| `POST /space/sessions` | body: JSON object | 201 | 400, 401, 404, 422 | Start a session in `path` that stands beside the session `near` in the headset, in its group, until it is moved. The listing and the trust record gate it exactly as they gate `POST /projects/session`, which does the starting; a folder inside a listed repo is taken as that repo, since a session's own folder is the one an agent knows. |
| `DELETE /space/planes/{plane_id}` | `?by`: string = "" | 204 | 401, 404, 422 | Close a page or window; its pose goes with it. No `by` is the person, and the session it stood beside is told. An agent passes its own name as `by`, as it does opening one, and nobody is told: what an agent closed is its own news. Never a session — none is kept here. |
| `PUT /space/poses/{key}` | body: JSON object | 204 | 400, 401, 404, 422 | `{x, y, z, yaw, pitch?, roll?, scale?, group?, minimized?, pin?}` for `session:<id>`, `plane:<id>`, `manager`, `projects`, `launcher`, `monitor`, `camera` or `why`. The headset's to call. |

### saying

| Route | Arguments | Answers | Errors | What it does |
|---|---|---|---|---|
| `POST /sessions/{session_id}/audio` | `?route`: string (auto, keyboard or socket), `?deliver`: boolean = true (false to transcribe only, when the person wants to read it first), `?seconds`: number (how long the clip runs, as the phone measured it — recorded, never used), form `{file}` | 201 | 400, 401, 404, 413, 415, 422 | Speaking to a session: the clip lands on the Mac and utt turns it into text. |
| `POST /sessions/{session_id}/image` | form `{file}` | 200 | 400, 401, 404, 413, 415, 422 | Take a picture from the phone and keep it, so a message can name where it is. |
| `POST /sessions/{session_id}/say` | `?route`: string (auto, keyboard or socket), `?prepared`: boolean = false (true when these words were already shown on the card, chain included), body `{text, images?}` | 200 | 401, 404, 422 | Put words into a session. The other half of an upload the person asked to read first. |
<!-- /generated:http -->
