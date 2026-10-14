# The manager

> Built, not planned. `docs/control-surface.md` is the plan this is the first two thirds of.

One Claude Agent SDK conversation lives inside the daemon. The phone reaches it by swiping the
rail one screen to the left, and it can read every session on this Mac, speak into them, set
their standing orders, start new ones, change this Mac's switches, and move the phone's own
screen. What it may not do is the load-bearing half, and it is one sentence: **the manager never
types into a pane.**

## The shape

```
phone                     daemon
  panel  ──POST /manager/say──▶  talk.say("person", …)  ─┐
  poll   ──GET  /manager?since=─▶  the file, after the cursor
                                                          │
                              manager/agent.watch()  ◀────┘
                                     │
                                     ├─ client.query(…), held open, twelve tools
                                     ├─ each text block  ──▶ talk.say("manager", …)
                                     └─ each acting tool ──▶ talk.say("act", …)
```

Three decisions carry the whole thing.

**The conversation is a file with a cursor, not a stream.** There is no socket to hold open to a
phone in a pocket and no push that could carry a sentence being written, so `manager/talk.py` is
a numbered list on disk and the phone asks for everything after the id it holds. A phone that was
away for an hour catches up in one call. It is the same answer `briefings` reached, for the same
reason, and it is why nothing is lost to a daemon restart.

**Held open, so it is a session like any other.** One `ClaudeSDKClient` lives as long as the
daemon, so Claude Code lists it as `deckhand-manager` with an inbox socket and any session can
`SendMessage` it; it answers with `SendMessage` back, and the turn shows in the panel without
buzzing the phone. It was one `query()` per thing said once, alive for seconds and so never
findable. A restart reopens it with `resume=` the SDK session id kept in the conversation file. A
resume that never answers is dropped once and the panel is told — otherwise a pruned SDK
transcript would leave a manager that could never reopen and no way back from the phone.

**The phone never waits for a model.** `POST /manager/say` answers the moment the words are
written down. The panel draws them at once and polls at one second while `working` is true.

## The facade

Twelve in-process tools over this daemon's own modules — a tool call is a function call, with no
HTTP round trip through the Mac's own front door and no second copy of the auth. They answer in
plain lines rather than JSON: the manager is reading, not parsing a wire, and a page of quoted
braces costs more and reads worse than the same facts laid out.

| Tool | Reads or changes | Over |
|---|---|---|
| `list_sessions` | every live session in a line each | `sessions`, `artifacts`, `tasks`, `briefings` |
| `read_session` | briefing, asks, orders, chain, slips, last turns | `briefings`, `orders`, `filters`, `reading` |
| `list_projects` | folders a session could start in, filtered | `projects.sources`, `projects.starting` |
| `read_settings` | the switches, global or resolved for a folder | `settings.wants` |
| `read_context` | every CLAUDE.md a folder's session is loaded with | `reading.context` |
| `say_to_session` | words into a session's own inbox | `deliver`, socket route only |
| `set_orders` | what a session keeps in mind | `orders.kept` |
| `start_session` | opens a terminal and starts Claude Code | `projects.starting` |
| `start_scratch_session` | makes a folder under the sandbox and starts one there | `projects.starting` |
| `set_switch` | one switch, globally or for one folder | `settings.wants` |
| `focus_session` | brings a pane to the front; types nothing | `sessions.focus` |
| `show_on_phone` | moves the phone's own screen | `manager/talk`, then the app |

Every tool description is in `prompts/manager.md`'s frontmatter and not in the code, because a
tool description is prompt. A test asserts the two lists have not drifted apart — a tool with no
description raises on the first thing anybody says, on the daemon, with nobody watching.

**A session is named, not addressed.** `tools.find` takes a name or an id and prefers an exact
name, and a name that matches nothing comes back as a sentence listing what *is* live. A model
told only "not found" invents a second UUID; one handed the actual list does not.

## What it refuses, and why those and not others

The invariant the rest of this repo is built on decides the surface: the route is an authority
choice, not a transport choice. The manager is a Claude session, so its words reach another
session down that session's inbox socket, labelled as another agent carrying none of the
person's authority. `say_to_session` has no route parameter to pass — not a default it could
override, no parameter at all.

From *the manager never types into a pane* follow three refusals, enforced by absence rather
than by a check. There is no tool for any of them:

- **No stop, compact or clear.** Keystrokes the person presses. `clear` is the only irreversible
  thing in the app.
- **No rename.** `/rename` is Claude Code's own command typed into a pane.
- **No answering a slip.** A slip asks the *person*; a manager answering one speaks as them.

And one that is not about the keyboard:

- **No rewriting a filter chain.** A chain stands between a prompt and a session, and it is not
  for the thing being filtered to edit. Reading one is fine and `read_session` does.

`set_switch` deliberately excludes `route` for the same reason the whole list exists.

**No Codex thread.** Codex has no inbox for another agent: its only way in arrives as the person
typing. So `say_to_session` refuses a Codex session outright and sends nothing — the one refusal
here that is a check rather than an absence, because the session is on the same listing.

**`start_session` is allowed where `docs/agent-surface.md` refuses it.** That refusal is about an
agent starting a process nobody asked for. This one only ever runs because somebody spoke into
the panel, and both gates are unchanged: the folder must be on this Mac's own project list, and
Claude Code must already be trusted there.

## Making a folder, and why the sandbox is the whole of where

`start_session` needs a folder from this Mac's own project list, so a task with no project had
nowhere to go at all: "go and collect these recordings" could only ever be answered with a
refusal and a request to name a folder, from a phone, by somebody who is not at the Mac.
`start_scratch_session` makes one — named after the task, under `~/dev/_sandbox`, the monorepo's
own scratch root (`~/dev/CLAUDE.md`: *Scratch → _sandbox*) — and starts a session in it. It is
the only thing on this surface that creates anything on the Mac, and four bounds are what keep
it from being a general "create a folder anywhere" verb:

- **The sandbox root or nothing.** The root is derived from the home directory rather than
  written out. A name carrying a `/`, a `\` or a `..` is **refused outright rather than
  sanitised** — `../../etc` slugified is `etc`, which lands inside the sandbox and is not what
  anybody asked for — and the folder is then resolved and its parent compared against the root,
  which is the check that holds whatever the name was.
- **A new folder, or an empty one.** Anything with a file in it is somebody else's scratch
  project and is refused by name. The empty case is reused on purpose: the folder is made
  before the terminal is opened, so a start that failed on iTerm would otherwise burn the name.
- **One trust entry, for a folder made a moment ago.** `starting.start` refuses a folder Claude
  Code has not been trusted in, and one created a second ago never has been, so `_trust` writes
  the same `hasTrustDialogAccepted` into `~/.claude.json` that the dialog writes — for that one
  path, read-modify-write through `os.replace`, never for anything outside the sandbox. What
  makes that honest rather than a safety question answered from another room is that the folder
  is **empty**: this daemon made it a moment ago and there is nothing in it to trust.
- **It still types nothing.** The session comes up with an empty conversation and the manager
  reaches it down its own inbox socket like any other, carrying none of the person's authority.

**What the trust dialog actually does, measured 2026-09-13.** Claude Code 2.1.270 on this Mac
shows no trust dialog in a folder it has never been trusted in: not under a trusted parent, not
under an untrusted one, with `--dangerously-skip-permissions` and without it, `--name` and
without it, empty folder and folder with files. It starts, writes its
`~/.claude/sessions/<pid>.json`, and files a `hasTrustDialogAccepted: **false**` entry for the
folder — which is why 125 folders under `_sandbox` are recorded and only the root reads as
trusted. Probed with a pty and a scrubbed `CLAUDE*` environment; that scrub is the part worth
keeping, because inside a Claude Code session the inherited `CLAUDE_CODE_CHILD_SESSION` marker
suppresses the session record and makes the probe say nothing at all. So the gate
`starting.start` enforces is this daemon's own rather than Claude Code's, and it is still the
right gate for a folder somebody else made: it is the daemon refusing to open a terminal in
somebody's project without the answer on file.

**None of this is a fence and the daemon should not pretend otherwise.** The manager holds no
token and makes no HTTP calls, so there is no `curl` around any of it — but everything above is
a design boundary rather than an authorisation check, and the second token
`docs/control-surface.md` and `docs/agent-surface.md` both ask for is still the thing that would
make it one.

## Driving the app

`show_on_phone` writes a `command` entry and the phone obeys it on its next poll. The command is
an entry like anything else, so the panel draws what it did in the line it did it.

Two things make it behave:

- **The phone obeys only commands newer than the cursor it opened with.** Without that, a
  relaunch replays every piece of navigation the manager has ever asked for, in order, at launch.
- **`ManagerDesk` has two slots, not one.** The rail owns which session is pushed and the
  session's own page owns which pane shows — two gates, two views. One slot would
  lose the first of them whenever a run asked for both, which is exactly what "open deckhand and
  show me its slips" is, and it is the first thing the manager actually did.

Six verbs today: `open_session`, `close_session`, `open_pane`, `open_settings`, `open_projects`,
`refresh`. They are cheap because the gates behind them already existed. The other twenty of
`control-surface.md`'s twenty-two presentation gates are still `@State` private to their views,
and each is a line on `ManagerDesk` plus a case in `ManagerRoute` when it is wanted.

## What is not built

- **No second token.** See above.
- **No `manager_model` switch.** The model is `prompts/manager.md`'s, and changing it is an edit
  and a restart. Adding one means touching `Wants`, the settings document, the wire and the
  settings screen for a knob nobody has asked to turn yet.
- **No file tools.** `Read`, `Glob` and `Grep` would make the manager far more capable and would
  widen the phone's reach from "what a session touched" to "anything on the Mac". If it needs a
  file read, it can ask a session to read it.
- **The panel polls only while it is open.** A command cannot reach a phone that has swiped away
  from the panel until it swipes back.
- **No streaming below the block.** Text arrives one block at a time, which on a run that calls
  four tools is already the difference between a live conversation and a spinner.

## Sources

`daemon/src/deckhand_daemon/manager/` (its `__init__.py` is the map),
`daemon/src/deckhand_daemon/prompts/manager.md`, `Sources/DeckhandKit/Manager/`,
`deckhand/Views/Manager/`, `daemon/tests/manager/test_manager.py`,
`Tests/DeckhandKitTests/Wire/ClientTests+Manager.swift`, `UITests/ManagerPanelTests.swift`.

## Live, and away from the panel

**The run in flight is drawn as it goes.** The SDK streams tokens (`include_partial_messages`),
and `agent.py` keeps the half-written sentence and the tool it is in — in memory, never in the
file, because half a sentence is not an entry. `GET /manager` carries both as `partial` and
`doing`; the panel draws the sentence as a card and the tool in the working line, and the block
replaces it as an entry on the same poll. The poll loop restarts when `working` flips, so a send
is followed by a one-second pace at once rather than after a four-second rest.

**What is said is drawn before the Mac has it.** A typed send is on screen, dimmed, the moment
it is sent, and goes back into the field if the Mac never took it. A clip shows *Hearing…* while
utt works and, under the same `confirms` preference a session's clip uses, lands on the review
card rather than going straight in — a mishearing here is an instruction to every session.

**A message nobody is watching for is pushed.** The panel polls only while it is on screen, so
the daemon's own record of the last poll (`agent.watched`, ten seconds) is the whole of how it
knows. A `manager` or `note` entry written while unwatched goes out as a plain notification
(`push.told`, the app's own *device* token, `thread-id: manager`); a tap opens the panel. A run
that starts unwatched gets `prompts/manager-away.md` added to its system prompt — one message,
lock-screen length, no markdown — and every run is told the first line of each message must
stand alone (`<lock_screen>`), because a person can pocket the phone halfway through one.
