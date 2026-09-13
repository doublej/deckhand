"""What the manager may change, and the two things it may not touch at all.

The manager is a Claude session like any other, so the invariant the rest of this daemon is
built on decides its whole surface: **the route is an authority choice, not a transport choice.**
Words from the keyboard route arrive as the person at the machine; words down a session's own
inbox socket arrive labelled as another agent carrying none of that authority. The manager is
the second thing, always, so `say_to_session` has no route parameter to pass — not a default it
could override, no parameter at all.

That one rule draws the whole line, and it is short enough to state: **the manager never types
into a pane.** From it follow the three refusals, which are enforced by absence rather than by a
check — there is no tool for any of them:

- **No stop, compact or clear.** Those are keystrokes the person presses, and `clear` is the
  only irreversible thing in the app.
- **No rename.** `/rename` is Claude Code's own command typed into a pane, which is the pane.
- **No answering a slip.** A slip asks the person; a manager answering one is the manager
  speaking as them into a session, which is the same laundering under another name.

And one that is not about the keyboard: **no rewriting a filter chain.** A chain is what stands
between a prompt and a session, and an agent that can edit it can remove the step that would
have stopped it. Reading one is fine and `tools.one` does.

Everything else is here, because the person is holding the phone this ran from. `start_session`
is deliberately allowed where `docs/agent-surface.md` refuses it: that refusal is about an agent
starting a process nobody asked for, and this one only ever runs because somebody spoke into the
panel. Both gates it inherits are unchanged — the folder must be on this Mac's own project list,
and Claude Code must already be trusted there.

`start_scratch_session` is the one thing here that **makes** something on the Mac, and the bound
is why it is not a general "create a folder" verb: it is the sandbox or it is nothing. A task
with no project on this Mac had nowhere to go at all before it, so the only answer left was a
refusal. `projects.starting.scratch_folder` holds the whole of where; read it before widening.
"""

from __future__ import annotations

from .. import deliver, sessions
from ..log import log
from ..orders import kept
from ..projects import sources, starting
from ..settings import wants
from . import talk
from .tools import find, missing, said

#: The switches a folder or this Mac can be given an answer for. `route` is deliberately not one
#: of them: the route is the authority choice and it is the person's, made on their own screen.
SWITCHES = ("finished", "slips", "called", "chase", "subagents", "session_model", "summary_model")
#: What the phone will act on. Anything else comes back as a refusal naming these, because a
#: model handed the list will use it and a model told only "no" will invent a second verb.
ACTIONS = ("open_session", "close_session", "open_pane", "open_settings", "open_projects",
           "refresh")
#: The panes a session's page has, in the order they are swiped through.
PANES = ("summary", "slips", "transcript", "files", "orders")


def speak(wanted: str, text: str) -> dict:
    """Put words into a session's own inbox, as another agent. Never as the person."""
    session = find(wanted)
    if session is None:
        return missing(wanted)
    text = text.strip()
    if not text:
        return said("nothing to say — say_to_session needs the words themselves.")
    by, error = deliver.deliver(session, text, route="socket")
    if error:
        talk.say("act", f"could not reach {session.name}: {error}")
        return said(f"it did not go in: {error}")
    talk.say("act", f"said to {session.name}: {_short(text)}")
    return said(
        f"delivered to {session.name} over the {by} route. It arrived labelled as another Claude "
        f"session, so that session knows it does not carry the person's authority — and a busy "
        f"session queues it until its turn ends. Nothing comes back; ask again in a minute to "
        f"see what it did."
    )


def order(wanted: str, text: str) -> dict:
    """Set what a session is to keep in mind, carried in front of every prompt it is sent."""
    session = find(wanted)
    if session is None:
        return missing(wanted)
    written = kept.save(session.session_id, text)
    talk.say("act", f"standing orders for {session.name}: {_short(written) or '(cleared)'}")
    if not written:
        return said(f"{session.name} now has no standing orders — nothing is added to its prompts.")
    return said(f"{session.name}'s standing orders are now: {written}")


def begin(wanted: str) -> dict:
    """Open a terminal in a folder on this Mac and start Claude Code in it."""
    found, _ = sources.catalog()
    lowered = (wanted or "").strip().lower()
    match = next(
        (p for p in found if p.name.lower() == lowered or p.path.lower() == lowered),
        next((p for p in found if lowered and lowered in p.relative.lower()), None),
    )
    if match is None:
        return said(f"no project called {wanted!r} on this Mac. Use list_projects to find it.")
    if match.path not in starting.trusted():
        return said(
            f"{match.name} has never been trusted by Claude Code, so a session started there "
            f"would stop at a trust prompt nobody can answer. The person has to open it once "
            f"themselves."
        )
    session, error = starting.start(match.path)
    if session is None:
        talk.say("act", f"could not start a session in {match.name}: {error}")
        return said(f"it did not start: {error}")
    sources.forget()
    talk.say("act", f"started {session.name} in {match.relative or match.path}")
    return said(f"{session.name} is running in {match.path}.")


def scratch(task: str) -> dict:
    """Make a folder under the sandbox for a task with no home, and start a session in it."""
    folder, why = starting.scratch_folder(task)
    if folder is None:
        return said(why)
    session, error = starting.start(str(folder))
    if session is None:
        talk.say("act", f"made {folder.name} but nothing started in it: {error}")
        return said(f"the folder is there and nothing started in it: {error}")
    sources.forget()
    talk.say("act", f"started {session.name} in a new scratch folder, {folder.name}")
    return said(
        f"{session.name} is running in {folder}, a folder made for this and holding nothing "
        f"else. Say what the work is with say_to_session — it has been told nothing yet."
    )


def switch(folder: str, key: str, value: str) -> dict:
    """Change one of this Mac's switches — globally, or for one folder."""
    if key not in SWITCHES:
        return said(f"{key!r} is not a switch. They are: {', '.join(SWITCHES)}.")
    settled = _value(key, value)
    if settled is None:
        return said(f"{value!r} is not an answer for {key}. Say on or off, or a model name.")
    document = wants.document()
    if folder:
        projects = dict(document.get("projects") or {})
        projects[folder] = {**(projects.get(folder) or {}), key: settled}
        document["projects"] = projects
    else:
        document[key] = settled
    written = wants.save(document)
    where = f"in {folder}" if folder else "on this whole Mac"
    now = (written.get("projects", {}).get(folder, {}) if folder else written).get(key)
    if now != settled:
        return said(f"the Mac refused {value!r} for {key}. It kept {now!r}.")
    talk.say("act", f"{key} is now {settled} {where}")
    return said(f"{key} is {settled} {where}.")


def on_phone(action: str, target: str) -> dict:
    """Ask the phone to go somewhere. It obeys the next time it polls, which is within a second.

    A command is an entry in the conversation like anything else, so the panel draws what it did
    in the line it did it — and the phone obeys only commands newer than the cursor it opened
    with, which is what stops a relaunch replaying yesterday's navigation.
    """
    if action not in ACTIONS:
        return said(f"{action!r} is not something the phone does. It does: {', '.join(ACTIONS)}.")
    if action == "open_pane" and target not in PANES:
        return said(f"{target!r} is not a pane. They are: {', '.join(PANES)}.")
    said_as = target
    if action == "open_session":
        session = find(target)
        if session is None:
            return missing(target)
        target, said_as = session.session_id, session.name
    talk.say("command", _phrased(action, said_as),
             command={"action": action, "target": target})
    return said(f"asked the phone to {_phrased(action, said_as)}. It has not been read yet.")


def focus(wanted: str) -> dict:
    """Bring a session's iTerm pane to the front on the Mac. Types nothing into it."""
    session = find(wanted)
    if session is None:
        return missing(wanted)
    if not sessions.focus(session):
        return said(f"{session.name} has no pane iTerm will answer for, so nothing to bring up.")
    talk.say("act", f"brought {session.name} to the front on the Mac")
    return said(f"{session.name} is at the front on the Mac.")


def _phrased(action: str, target: str) -> str:
    return {
        "open_session": f"open {target}",
        "close_session": "go back to the list",
        "open_pane": f"show the {target} pane",
        "open_settings": "open Settings",
        "open_projects": "open the project picker",
        "refresh": "refresh now",
    }[action]


def _value(key: str, value: str) -> object | None:
    """A switch's answer out of what a model typed. Models write yes, true, on and 1 alike."""
    if key.endswith("_model"):
        return value.strip()
    lowered = value.strip().lower()
    if lowered in ("on", "yes", "true", "1"):
        return True
    if lowered in ("off", "no", "false", "0"):
        return False
    return None


def _short(text: str) -> str:
    one_line = " ".join(text.split())
    return one_line if len(one_line) <= 90 else one_line[:87] + "…"


def server(described: dict[str, str]):
    """Every tool the manager has, in one in-process server.

    In-process, so a tool call is a function call against this daemon's own modules — the phone
    reading a moment later reads what this wrote, with no HTTP round trip through the Mac's own
    front door and no second copy of the auth. `described` is what the model is told each tool
    does, out of `prompts/manager.md`: a tool description is prompt, and every prompt in this
    daemon lives in a file.
    """
    from claude_agent_sdk import create_sdk_mcp_server, tool

    from . import tools as reading

    @tool("list_sessions", described["list_sessions"], {})
    async def list_sessions(_: dict) -> dict:
        return reading.listing()

    @tool("read_session", described["read_session"], {"session": str, "turns": int})
    async def read_session(args: dict) -> dict:
        session = find(str(args.get("session", "")))
        if session is None:
            return missing(str(args.get("session", "")))
        return reading.one(session, max(0, min(int(args.get("turns") or 0), 20)))

    @tool("list_projects", described["list_projects"], {"query": str})
    async def list_projects(args: dict) -> dict:
        return reading.catalogue(str(args.get("query", "")), limit=30)

    @tool("read_settings", described["read_settings"], {"folder": str})
    async def read_settings(args: dict) -> dict:
        return reading.switches(str(args.get("folder", "")))

    @tool("read_context", described["read_context"], {"session": str})
    async def read_context(args: dict) -> dict:
        session = find(str(args.get("session", "")))
        if session is None:
            return missing(str(args.get("session", "")))
        return reading.loaded(session)

    @tool("say_to_session", described["say_to_session"], {"session": str, "text": str})
    async def say_to_session(args: dict) -> dict:
        return speak(str(args.get("session", "")), str(args.get("text", "")))

    @tool("set_orders", described["set_orders"], {"session": str, "text": str})
    async def set_orders(args: dict) -> dict:
        return order(str(args.get("session", "")), str(args.get("text", "")))

    @tool("start_session", described["start_session"], {"project": str})
    async def start_session(args: dict) -> dict:
        return begin(str(args.get("project", "")))

    @tool("start_scratch_session", described["start_scratch_session"], {"task": str})
    async def start_scratch_session(args: dict) -> dict:
        return scratch(str(args.get("task", "")))

    @tool("set_switch", described["set_switch"], {"folder": str, "key": str, "value": str})
    async def set_switch(args: dict) -> dict:
        return switch(str(args.get("folder", "")), str(args.get("key", "")),
                      str(args.get("value", "")))

    @tool("focus_session", described["focus_session"], {"session": str})
    async def focus_session(args: dict) -> dict:
        return focus(str(args.get("session", "")))

    @tool("show_on_phone", described["show_on_phone"], {"action": str, "target": str})
    async def show_on_phone(args: dict) -> dict:
        return on_phone(str(args.get("action", "")), str(args.get("target", "")))

    made = [list_sessions, read_session, list_projects, read_settings, read_context,
            say_to_session, set_orders, start_session, start_scratch_session, set_switch,
            focus_session, show_on_phone]
    if len(made) != len(TOOLS):
        log.warning("the manager's tool list and TOOLS have drifted apart")
    return create_sdk_mcp_server(name="deckhand", tools=made)


#: The names the model calls them by once the server above is mounted. Spelled out rather than
#: derived, because this is also the allow-list: a tool that is not on it is not callable, so a
#: new tool nobody added here is off rather than quietly on.
TOOLS = tuple(
    f"mcp__deckhand__{name}"
    for name in ("list_sessions", "read_session", "list_projects", "read_settings",
                 "read_context", "say_to_session", "set_orders", "start_session",
                 "start_scratch_session", "set_switch", "focus_session", "show_on_phone")
)
