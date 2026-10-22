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

Everything else is here, because the person is holding the phone this ran from. The two verbs
that **make** a session rather than speak to one are next door in `opening.py`, where the whole
of what they may open is written down — this file is what may be done to a session that exists.
"""

from __future__ import annotations

from .. import deliver, sessions
from ..log import log
from ..orders import kept
from ..settings import wants
from . import talk
from .opening import begin, scratch
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
    # Codex has no inbox for another agent. Its only lane arrives as the person typing, and the
    # manager speaking down it would be the manager speaking as them.
    if session.provider == "codex":
        return said(f"{session.name} is a Codex thread. Codex's only way in carries the person's "
                    f"own authority, and there is no inbox for another agent — nothing was sent. "
                    f"The person has to say this to it themselves.")
    text = text.strip()
    if not text:
        return said("nothing to say — say_to_session needs the words themselves.")
    by, error = deliver.deliver(session, text, route="socket")
    if error:
        talk.say("act", f"could not reach {session.name}: {error}")
        return said(f"it did not go in: {error}")
    talk.say("act", f"said to {session.name}: {_short(text)}")
    return said(
        f"delivered to {session.name} over the {by} route. It arrived labelled as another agent, "
        f"so that session knows it does not carry the person's authority — and a busy "
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
    """Show a session's tmux pane on the Mac. Types nothing into it."""
    session = find(wanted)
    if session is None:
        return missing(wanted)
    if not sessions.focus(session):
        return said(f"{session.name} is not in a tmux pane, so nothing to bring up.")
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
    from claude_agent_sdk import create_sdk_mcp_server

    return create_sdk_mcp_server(name="deckhand", tools=build(described))


#: What a tool may be called without, its handler filling in the default. The SDK's `{name: type}`
#: shorthand marks every key required, so an agent leaving out `turns` was refused, and one meaning
#: "every machine" had to guess `""` for `machine`.
OPTIONAL = {"list_sessions": {"machine", "state"}, "read_session": {"turns", "before", "parts"},
            "read_context": {"whole"}, "list_projects": {"query", "machine"},
            "read_settings": {"folder"}, "start_session": {"machine", "model"},
            "start_scratch_session": {"model"}, "set_switch": {"folder"}, "look": {"session"}}


def _loosened(one):
    """`one` with its shorthand written out as JSON Schema, and only what it needs required."""
    import dataclasses

    kinds = {str: "string", int: "integer", bool: "boolean"}
    shape = {name: {"type": kinds[kind]} for name, kind in one.input_schema.items()}
    return dataclasses.replace(one, input_schema={
        "type": "object", "properties": shape,
        "required": [name for name in shape if name not in OPTIONAL.get(one.name, ())]})


def build(described: dict[str, str]) -> list:
    """The same tools, unmounted. `server` mounts them for the run in this daemon;
    `POST /manager/tools/{name}` runs one for `deckhand-manager-mcp`, a session acting as the
    manager — the same functions in this same process either way, so there is one manager surface
    and not two that drift."""
    from claude_agent_sdk import ToolAnnotations, tool

    # The same annotation mcp/server.py hands its own readers. read_only_hint is the one
    # the SDK acts on rather than merely shows: it is what lets a turn that reads three
    # sessions call them at once instead of one after another.
    reads = ToolAnnotations(read_only_hint=True, open_world_hint=False)

    from . import tools as reading

    @tool("list_sessions", described["list_sessions"], {"machine": str, "state": str},
          annotations=reads)
    async def list_sessions(args: dict) -> dict:
        return await reading.listing(str(args.get("machine", "")), str(args.get("state", "")))

    @tool("read_session", described["read_session"],
          {"session": str, "turns": int, "before": int, "parts": str}, annotations=reads)
    async def read_session(args: dict) -> dict:
        session = find(str(args.get("session", "")))
        if session is None:
            return missing(str(args.get("session", "")))
        return await reading.one(session, max(0, min(int(args.get("turns") or 0), 20)),
                                 max(0, int(args.get("before") or 0)), str(args.get("parts", "")))

    @tool(
        "list_projects",
        described["list_projects"],
        {"query": str, "machine": str},
        annotations=reads,
    )
    async def list_projects(args: dict) -> dict:
        return await reading.catalogue(
            str(args.get("query", "")), str(args.get("machine", "")), limit=30
        )

    @tool("read_settings", described["read_settings"], {"folder": str}, annotations=reads)
    async def read_settings(args: dict) -> dict:
        return reading.switches(str(args.get("folder", "")))

    @tool("read_context", described["read_context"], {"session": str, "whole": bool},
          annotations=reads)
    async def read_context(args: dict) -> dict:
        session = find(str(args.get("session", "")))
        if session is None:
            return missing(str(args.get("session", "")))
        return await reading.loaded(session, bool(args.get("whole")))

    @tool("say_to_session", described["say_to_session"], {"session": str, "text": str})
    async def say_to_session(args: dict) -> dict:
        return speak(str(args.get("session", "")), str(args.get("text", "")))

    @tool("set_orders", described["set_orders"], {"session": str, "text": str})
    async def set_orders(args: dict) -> dict:
        return order(str(args.get("session", "")), str(args.get("text", "")))

    @tool("start_session", described["start_session"],
          {"project": str, "machine": str, "model": str})
    async def start_session(args: dict) -> dict:
        return await begin(str(args.get("project", "")), str(args.get("machine", "")),
                           str(args.get("model", "")))

    @tool("start_scratch_session", described["start_scratch_session"], {"task": str, "model": str})
    async def start_scratch_session(args: dict) -> dict:
        return scratch(str(args.get("task", "")), str(args.get("model", "")))

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

    @tool("look", described["look"], {"path": str, "session": str}, annotations=reads)
    async def look(args: dict) -> dict:
        from .looking import look as get

        return await get(str(args.get("path", "")), str(args.get("session", "")))

    made = [list_sessions, read_session, list_projects, read_settings, read_context,
            say_to_session, set_orders, start_session, start_scratch_session, set_switch,
            focus_session, show_on_phone, look]
    if len(made) != len(TOOLS):
        log.warning("the manager's tool list and TOOLS have drifted apart")
    return [_loosened(one) for one in made]


#: The names the model calls them by once the server above is mounted. Spelled out rather than
#: derived, because this is also the allow-list: a tool that is not on it is not callable, so a
#: new tool nobody added here is off rather than quietly on.
TOOLS = tuple(
    f"mcp__deckhand__{name}"
    for name in ("list_sessions", "read_session", "list_projects", "read_settings",
                 "read_context", "say_to_session", "set_orders", "start_session",
                 "start_scratch_session", "set_switch", "focus_session", "show_on_phone", "look")
)
