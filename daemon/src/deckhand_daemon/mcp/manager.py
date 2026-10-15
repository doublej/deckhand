"""The manager's twelve tools, for a session the person wants to manage from.

The panel's manager is a Claude session inside the daemon, and the phone is how it is spoken to.
This is the same surface for a session at the keyboard: list and read every session on every
machine, speak into one, set its orders, start one, change this Mac's switches, bring a pane to
the front, and move the phone's screen. Each call runs the manager's own tool inside the daemon
(`POST /manager/tools/{name}`), so what it does is written into the manager's conversation and
the panel shows it.

**It never types into a pane.** `say_to_session` goes down the session's inbox socket and arrives
labelled as another agent, carrying none of the person's authority. There is no tool to stop,
compact, clear, close or rename a session, to answer a slip, or to edit a filter chain — those are
the person's own presses, and `manager/doing.py` says why for each.

Installed apart from `deckhand-mcp` on purpose (`claude mcp add deckhand-manager -- uv run
--project <checkout>/daemon deckhand-manager-mcp`): every session gets that one, and only a
session the person chose should be able to change this Mac's switches.
"""

from __future__ import annotations

import asyncio
import dataclasses

from claude_agent_sdk import create_sdk_mcp_server
from mcp.server.stdio import stdio_server

from .. import prompts
from ..manager import doing
from ..manager.tools import said
from . import here


def _forwarded(name: str):
    async def run(args: dict) -> dict:
        answer = await here.reach("POST", f"/manager/tools/{name}", json=args)
        if "error" in answer:
            return {**said(answer["error"]), "is_error": True}
        return said(answer["text"])

    return run


def build():
    """The manager's tools as they are described to it, each forwarded to the daemon."""
    described = prompts.load("manager").settings["tools"]
    forwarded = [dataclasses.replace(made, handler=_forwarded(made.name))
                 for made in doing.build(described)]
    server = create_sdk_mcp_server(name="deckhand-manager", tools=forwarded)["instance"]
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
