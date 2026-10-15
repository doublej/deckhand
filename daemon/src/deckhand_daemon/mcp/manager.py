"""The manager's twelve tools and the person's tmux, for a session the person wants to manage from.

The panel's manager is a Claude session inside the daemon, and the phone is how it is spoken to.
This is the same surface for a session at the keyboard: list and read every session on every
machine, speak into one, set its orders, start one, change this Mac's switches, bring a pane to
the front, and move the phone's screen. Plus the session server's own `tmux_tree` and
`tmux_arrange` (`mcp/tmux.py`), run where this server runs, so from off this Mac too the person's
tmux can be read and its windows renamed, grouped, moved, joined and laid out. Each call runs the manager's own tool inside the daemon
(`POST /manager/tools/{name}`), so what it does is written into the manager's conversation and
the panel shows it.

**It never types into a pane.** `say_to_session` goes down the session's inbox socket and arrives
labelled as another agent, carrying none of the person's authority. There is no tool to stop,
compact, clear, close or rename a session, to answer a slip, or to edit a filter chain — those are
the person's own presses, and `manager/doing.py` says why for each.

Installed apart from `deckhand-mcp` on purpose (`claude mcp add deckhand-manager -- uv run
--project <checkout>/daemon deckhand-manager-mcp`): every session gets that one, and only a
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
from ..manager import doing
from ..manager.tools import said
from . import here, tmux


def _forwarded(name: str):
    async def run(args: dict) -> dict:
        answer = await here.reach("POST", f"/manager/tools/{name}", json=args)
        if "error" in answer:
            return {**said(answer["error"]), "is_error": True}
        return said(answer["text"])

    return run


async def _tree(args: dict) -> dict:
    return _answered(await tmux.tmux_tree())


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
    SdkMcpTool("tmux_tree", inspect.cleandoc(tmux.tmux_tree.__doc__), {"type": "object", "properties": {}}, _tree,
               ToolAnnotations(readOnlyHint=True, openWorldHint=False)),
    SdkMcpTool("tmux_arrange", inspect.cleandoc(tmux.tmux_arrange.__doc__), ARRANGE, _arrange,
               ToolAnnotations(openWorldHint=False)),
]


def build(forwarded: bool = True):
    """The manager's tools as they are described to it — each forwarded to the daemon, or for
    `/mcp` (`remote.py`), which is the daemon, run where they are."""
    described = prompts.load("manager").settings["tools"]
    made = doing.build(described)
    if forwarded:
        made = [dataclasses.replace(one, handler=_forwarded(one.name)) for one in made]
    server = create_sdk_mcp_server(name="deckhand-manager", tools=made + TMUX_TOOLS)["instance"]
    server.instructions = __doc__
    return server


async def _serve() -> None:
    server = build()
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


def main() -> None:
    asyncio.run(_serve())


if __name__ == "__main__":
    main()
