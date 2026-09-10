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
                                     ├─ query(resume=…) with eleven tools
                                     ├─ each text block  ──▶ talk.say("manager", …)
                                     └─ each acting tool ──▶ talk.say("act", …)
```

Three decisions carry the whole thing.

**The conversation is a file with a cursor, not a stream.** There is no socket to hold open to a
phone in a pocket and no push that could carry a sentence being written, so `manager/talk.py` is
a numbered list on disk and the phone asks for everything after the id it holds. A phone that was
away for an hour catches up in one call. It is the same answer `briefings` reached, for the same
reason, and it is why nothing is lost to a daemon restart.

**One run per thing said, resumed rather than held open.** Nothing keeps a `ClaudeSDKClient`
alive. Each turn is a `query()` carrying `resume=` the last run's SDK session id, which lives in
the conversation file beside the entries. This daemon is restarted often enough that a long-lived
subprocess would be the thing that broke first. A resume that fails is retried once *without*
one and the panel is told the thread was lost — otherwise a pruned SDK transcript would leave a
manager that answered every message with the same error and no way back from the phone.

**The phone never waits for a model.** `POST /manager/say` answers the moment the words are
written down. The panel draws them at once and polls at one second while `working` is true.

## The facade

Eleven in-process tools over this daemon's own modules — a tool call is a function call, with no
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

**`start_session` is allowed where `docs/agent-surface.md` refuses it.** That refusal is about an
agent starting a process nobody asked for. This one only ever runs because somebody spoke into
the panel, and both gates are unchanged: the folder must be on this Mac's own project list, and
Claude Code must already be trusted there.

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
  session's own page owns which of its five panes shows — two gates, two views. One slot would
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
