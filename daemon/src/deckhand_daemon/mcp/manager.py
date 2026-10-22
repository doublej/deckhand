"""`deckhand-control`: the manager's tools and the person's tmux, lent to another agent.

**Not the manager.** The manager is a Claude session inside the daemon, spoken to from the phone's
panel; this server is its hands, lent to a session at the keyboard or an MCP client off this Mac
(a voice agent, say). Called "the manager MCP" once, which is how an agent asked to "brief the
manager" found it was holding the manager's tools and had no way to the manager itself.
`tell_manager` is that way: words into the manager's inbox, labelled as another agent.

This is the same surface: list and read every session on every
machine, speak into one, set its orders, start one, change this Mac's switches, bring a pane to
the front, and move the phone's screen. Plus the session server's own `tmux_tree` and
`tmux_arrange` (`mcp/tmux.py`), run where this server runs, so from off this Mac too the person's
tmux can be read and its windows renamed, grouped, moved, joined and laid out. Each call runs the
manager's own tool inside the daemon (`POST /manager/tools/{name}`), so what it does is written
into the manager's conversation — under the caller's name (`talk.caller`): a session's name over
stdio, the token's name over HTTP — and the panel shows who did it.

**It never types into a pane.** `say_to_session` goes down the session's inbox socket and arrives
labelled as another agent, carrying none of the person's authority. There is no tool to stop,
compact, clear, close or rename a session, to answer a slip, or to edit a filter chain — those are
the person's own presses, and `manager/doing.py` says why for each. Ending one is `request_end_session`:
a card on the person's phone, and only their Allow ends anything.

Installed apart from `deckhand-mcp` on purpose (`claude mcp add deckhand-control -- uv run
--project <checkout>/daemon deckhand-control-mcp`): every session gets that one, and only a
session the person chose should be able to change this Mac's switches. From off this Mac it is
`https://deckhand-mcp.jurrejan.com/mcp` with a manager-only bearer token (`remote.py`).
"""

from __future__ import annotations

import asyncio
import dataclasses
import inspect
import json
from typing import get_args

from claude_agent_sdk import SdkMcpTool, create_sdk_mcp_server
from mcp.server.stdio import stdio_server
from mcp.types import ToolAnnotations

from .. import prompts
from ..manager import doing, talk
from ..manager.tools import said
from . import here, tmux

#: What a model using this server is told. Short, because a voice agent pays for it every turn.
INSTRUCTIONS = """The tools the Deckhand manager uses, lent to you. You are not the manager and \
calling them does not reach it: to brief the manager — the agent behind the person's phone panel \
— use `tell_manager`. Each action you take shows in its panel under your name.

No tool stops, compacts, clears, closes or renames a session, answers a slip or edits a filter \
chain: those are the person's own presses. To end sessions, `request_end_session` asks the person on \
their phone. `say_to_session` and `tell_manager` arrive labelled as another agent, never as the \
person."""


def _caller() -> str:
    """Who is using this server: the token's name over HTTP, else the session above this process."""
    return talk.caller.get() or (here.mine() or {}).get("name") or "an agent"


def _forwarded(name: str):
    async def run(args: dict) -> dict:
        answer = await here.reach("POST", f"/manager/tools/{name}", json=args,
                                  headers={"x-deckhand-for": _caller()})
        if "error" in answer:
            return {**said(answer["error"]), "is_error": True}
        return {**said(answer["text"]), "is_error": bool(answer.get("is_error"))}

    return run


async def _tree(args: dict) -> dict:
    return _answered(await tmux.tmux_tree(str(args.get("match", ""))))


async def _tell(args: dict) -> dict:
    """Brief the manager — the agent behind the person's phone panel — in your own words: what
    you did, what failed, what it should follow up. It arrives in the manager's inbox labelled as
    another agent with your name on it, carrying none of the person's authority. Nothing comes
    back here: the manager answers the person in the panel."""
    found = await here.reach("GET", "/manager/session")
    if "error" in found:
        return _answered({"error": f"the manager is not running: {found['error']}"})
    text = f"From {_caller()}, over Deckhand's MCP: {str(args.get('text', '')).strip()}"
    answered = await here.reach("POST", f"/sessions/{found['session_id']}/say",
                                params={"route": "socket"}, json={"text": text})
    if "error" in answered:
        return _answered(answered)
    return _answered({"went": bool(answered.get("delivered")),
                      "why": answered.get("delivery_error")})


async def _end(args: dict) -> dict:
    """Request the person's approval to stop, close, end or terminate sessions, on any machine,
    by name or id — the only way to do that from here: one Allow/Deny card on their phone naming
    each and your `why`. **This ends nothing** — only their Allow does, and
    nothing tells you which they chose; `list_sessions` later shows it. For cleanup the person
    asked for. Refused unless each name is exactly one Claude session with a process."""
    return _answered(await here.reach("POST", "/end-requests", json={
        "sessions": list(args.get("names") or []), "why": str(args.get("why", "")),
        "asker": _caller()}))


async def _arrange(args: dict) -> dict:
    return _answered(await tmux.tmux_arrange(**args))


def _answered(answer: dict) -> dict:
    return {**said(json.dumps(answer, ensure_ascii=False)), "is_error": "error" in answer}


#: `tmux_arrange`'s arguments, spelled out because the SDK takes a JSON schema, not a signature.
ARRANGE = {"type": "object", "required": ["action", "target"], "properties": {
    "action": {"type": "string", "enum": list(get_args(tmux.Action))},
    "target": {"type": "string"}, "to": {"type": "string"}, "name": {"type": "string"},
    "layout": {"type": "string", "enum": list(tmux.LAYOUTS)},
    "split": {"type": "string", "enum": ["right", "below"]}}, "additionalProperties": False}

TMUX_TOOLS = [
    SdkMcpTool("tmux_tree", inspect.cleandoc(tmux.tmux_tree.__doc__),
               {"type": "object", "properties": {"match": {"type": "string"}}}, _tree,
               ToolAnnotations(readOnlyHint=True, openWorldHint=False)),
    SdkMcpTool("tmux_arrange", inspect.cleandoc(tmux.tmux_arrange.__doc__), ARRANGE, _arrange,
               ToolAnnotations(openWorldHint=False)),
]

#: The two that are this server's own and not the manager's: the manager does not brief itself,
#: and it does not ask the person to end sessions, which the panel does by the person's own tap.
OWN_TOOLS = [
    SdkMcpTool("tell_manager", inspect.cleandoc(_tell.__doc__),
               {"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]},
               _tell, ToolAnnotations(openWorldHint=False)),
    SdkMcpTool("request_end_session", inspect.cleandoc(_end.__doc__),
               {"type": "object", "required": ["names", "why"], "properties": {
                   "names": {"type": "array", "items": {"type": "string"}},
                   "why": {"type": "string"}}},
               _end, ToolAnnotations(openWorldHint=False)),
]


def build(forwarded: bool = True):
    """The manager's tools as they are described to it — each forwarded to the daemon, or for
    `/mcp` (`remote.py`), which is the daemon, run where they are."""
    described = prompts.load("manager").settings["tools"]
    made = doing.build(described)
    if forwarded:
        made = [dataclasses.replace(one, handler=_forwarded(one.name)) for one in made]
    server = create_sdk_mcp_server(name="deckhand-control",
                                   tools=made + TMUX_TOOLS + OWN_TOOLS)["instance"]
    server.instructions = INSTRUCTIONS
    return server


async def _serve() -> None:
    server = build()
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


def main() -> None:
    asyncio.run(_serve())


if __name__ == "__main__":
    main()
