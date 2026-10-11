"""Which session this server belongs to, and how it reaches the daemon.

**The session is found by walking up the process tree, not out of the environment.**
`CLAUDE_CODE_SESSION_ID` is put into the environment of the shells Claude Code spawns for its Bash
tool, and an MCP server is not one of those — it is started before any of that and does not get
it. What it does have is an ancestor: `claude` itself, whose pid keys
`~/.claude/sessions/<pid>.json`, which is the same join the whole of Deckhand hangs off. A walk
rather than one `getppid()` because the launch line goes through `uv`, so the parent is uv and
`claude` is its grandparent. The variable is still read first, free and correct where it is set.

**The folder comes from that record too, never from `os.getcwd()`.** An MCP server inherits the
cwd of whatever started it, and a slip written in the wrong folder is invisible to the phone
rather than an error anybody sees.

**The daemon is reached over the loopback with the pairing token**, which is a file this process
can read because it runs as the person. Not by importing the daemon's own modules: the routes
carry the filter chain, the folder's refusals and the delivery record, and none of that is in the
functions underneath them.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import httpx

from .. import config

# How far up to look for the `claude` that started this. Three would do — claude, uv, python —
# and the ceiling is only there so a strange tree ends the walk rather than the walk ending it.
ANCESTORS = 8
TIMEOUT = 20.0


def sessions_dir() -> Path:
    return Path(os.environ.get("DECKHAND_CLAUDE_HOME", Path.home() / ".claude")) / "sessions"


def _record(pid: int) -> dict | None:
    try:
        held = json.loads((sessions_dir() / f"{pid}.json").read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return held if isinstance(held, dict) and held.get("sessionId") else None


def _parent(pid: int) -> int | None:
    done = subprocess.run(["ps", "-o", "ppid=", "-p", str(pid)],
                          capture_output=True, text=True, check=False)
    parent = done.stdout.strip()
    return int(parent) if parent.isdigit() and int(parent) > 1 else None


def mine() -> dict | None:
    """This session's own record, or None when nothing above this process is a session.

    None is a real outcome, not a failure to handle later: run by hand from a terminal there is
    no session above, and every tool that needs one says so rather than guessing at the newest.
    """
    wanted = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    pid: int | None = os.getpid()
    for _ in range(ANCESTORS):
        pid = _parent(pid) if pid else None
        if pid is None:
            break
        if (held := _record(pid)) and (not wanted or held.get("sessionId") == wanted):
            return held
    return None


async def reach(method: str, path: str, **sent: object) -> dict:
    """One call to the daemon. Every expected failure comes back as `{"error": sentence, "code":
    WORD}`, the code being what the `deckhand` command turns into its exit status."""
    headers = {config.TOKEN_HEADER: config.token()}
    url = f"http://127.0.0.1:{config.PORT}{path}"
    try:
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            answered = await client.request(method, url, headers=headers, **sent)
    except httpx.HTTPError as error:
        return {"error": f"the Deckhand daemon is not answering on port {config.PORT}: {error}",
                "code": "DAEMON_DOWN"}
    if answered.status_code >= 400:
        detail = answered.text.strip()[:200]
        return {"error": f"the daemon refused that ({answered.status_code}): {detail}",
                "code": "REFUSED"}
    try:
        return answered.json()
    except ValueError:
        return {"error": "the daemon answered with something that is not JSON",
                "code": "BAD_ANSWER"}
